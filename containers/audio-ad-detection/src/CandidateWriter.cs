using System.Buffers.Binary;
using System.Text;

namespace AudioAdDetection;

/// <summary>
/// The candidate writer: a hand-rolled 44-byte-header, 5512 Hz mono s16le
/// file (the worker's own resampled stream — no extra package), written
/// under $MODEL_DIR/candidates/ with the naming scheme
/// <c>&lt;group&gt;_&lt;UTC-timestamp&gt;_&lt;duration&gt;s.wav</c>. A failed
/// write is reported back (the caller logs it) and never thrown into the
/// query loop.
/// </summary>
public static class CandidateWriter
{
    private const int SampleRate = 5512;
    private const int HeaderBytes = 44;
    private const int BitsPerSample = 16; // s16le

    /// <summary>The candidate file extension (kept here so the token lives in one file).</summary>
    public const string CandidateExt = ".wav";

    /// <summary>
    /// Builds the candidate file name (&lt;group&gt;_&lt;UTC-timestamp&gt;_&lt;duration&gt;s.wav).
    /// <paramref name="utcNow"/> is the fixed-timestamp injection seam:
    /// null resolves to <see cref="DateTime.UtcNow"/> at call time (a
    /// default parameter must be a compile-time constant, so the seam is
    /// nullable); a supplied value pins the timestamp in the name.
    /// </summary>
    public static string BuildFileName(string group, DateTime? utcNow = null, int durationSeconds = 0)
    {
        var now = utcNow ?? DateTime.UtcNow;
        return $"{group}_{now:yyyyMMddTHHmmssZ}_{durationSeconds}s.wav";
    }

    /// <summary>The candidate directory: $MODEL_DIR/candidates/ (created on demand).</summary>
    public static string CandidatesDir(WorkerConfig config) => Path.Combine(config.ModelDir, "candidates");

    /// <summary>
    /// Writes one candidate (44-byte-header, 5512 Hz, mono, 16-bit little
    /// endian). Returns false + the error text instead of throwing: a failed
    /// write is logged by the caller and never fatal to the query loop.
    /// </summary>
    public static bool TryWrite(WorkerConfig config, string fileName, float[] samples, out string? error)
    {
        error = null;
        try
        {
            var dir = CandidatesDir(config);
            Directory.CreateDirectory(dir);
            var path = Path.Combine(dir, fileName);
            var dataBytes = samples.Length * 2;
            using var stream = new FileStream(path, FileMode.Create, FileAccess.Write);
            using var writer = new BinaryWriter(stream);

            // RIFF chunk header
            writer.Write((uint)(36 + dataBytes));
            writer.Write(Encoding.ASCII.GetBytes("RIFF"));
            writer.Write(Encoding.ASCII.GetBytes("WAVE"));
            // fmt chunk: PCM (1), 1 channel, 5512 Hz, 16 bits per sample
            writer.Write((uint)16);
            writer.Write(Encoding.ASCII.GetBytes("fmt "));
            writer.Write((ushort)1); // audio format: PCM
            writer.Write((ushort)1); // channel count (mono)
            writer.Write((int)SampleRate);
            writer.Write((int)(SampleRate * 2)); // byte rate
            writer.Write((ushort)2); // block align
            writer.Write((ushort)BitsPerSample);
            // data chunk
            writer.Write((uint)dataBytes);
            writer.Write(Encoding.ASCII.GetBytes("data"));
            foreach (var sample in samples)
            {
                var clamped = (int)(Math.Clamp(sample, -1f, 1f) * short.MaxValue);
                writer.Write((short)clamped);
            }
            return true;
        }
        catch (Exception ex)
        {
            error = ex.Message;
            return false;
        }
    }

    /// <summary>
    /// Direct 44-byte-header read of a candidate s16le file (the manual
    /// single-file lane and the auto-promote insert decode this way — no
    /// FFmpeg; only the arbitrary-format directory lane pulls the decoder).
    /// </summary>
    public static bool TryReadSamples(string path, out float[] samples, out int sampleRate)
    {
        samples = [];
        sampleRate = 0;
        try
        {
            var bytes = File.ReadAllBytes(path);
            if (bytes.Length < HeaderBytes)
                return false;
            if (!bytes.AsSpan(0, 4).SequenceEqual(Encoding.ASCII.GetBytes("RIFF")) ||
                !bytes.AsSpan(8, 4).SequenceEqual(Encoding.ASCII.GetBytes("WAVE")))
                return false;
            var channels = BinaryPrimitives.ReadInt16LittleEndian(bytes.AsSpan(22, 2));
            sampleRate = BinaryPrimitives.ReadInt32LittleEndian(bytes.AsSpan(24, 4));
            var bitsPerSample = BinaryPrimitives.ReadInt16LittleEndian(bytes.AsSpan(34, 2));
            if (channels != 1 || bitsPerSample != 16)
                return false;
            var data = bytes.AsSpan(HeaderBytes);
            samples = new float[data.Length / 2];
            for (var i = 0; i < samples.Length; i++)
                samples[i] = BinaryPrimitives.ReadInt16LittleEndian(data.Slice(i * 2, 2)) / 32768f;
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }
}
