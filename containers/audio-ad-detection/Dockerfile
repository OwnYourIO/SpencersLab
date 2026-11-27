# Multi-stage: framework-dependent .NET 10 publish on the sdk, then the lean
# runtime image (no ASP.NET Core shared framework — R3 §1: the health/metrics
# surface is a plain System.Net.HttpListener, no Kestrel). Both 10.0 tags
# resolve to 10.0.15 on noble (amd64; the repo build is single-arch amd64).
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
# The restore layer is isolated from the app code so a csproj-only change
# does not bust the publish layer — the first cold forge build risks the
# 30-min ceiling, warm builds must stay fast (R3 §5).
COPY src/AudioAdDetection.csproj ./
RUN dotnet restore
COPY src/ ./
RUN dotnet publish -c Release -r linux-x64 --self-contained false -o /app/publish

FROM mcr.microsoft.com/dotnet/runtime:10.0
# renovate: datasource=github-releases depName=snapcast/snapcast
ARG SNAPCAST_VERSION=0.35.0
WORKDIR /app
COPY --from=build /app/publish ./
# The plain bookworm .deb is a SOXR build (libsoxr0 in Depends — the
# --sampleformat option exists) and pulls no audio-server dependency (R2 §4).
# The deb's version string is <ver>-1, so the URL stays version-stable under
# the ARG pin above.
RUN wget -q "https://github.com/snapcast/snapcast/releases/download/v${SNAPCAST_VERSION}/snapclient_${SNAPCAST_VERSION}-1_amd64_bookworm.deb" \
    && apt-get update \
    && apt-get install -y --no-install-recommends ./snapclient_*.deb \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f ./snapclient_*.deb
# ffmpeg + ffprobe: the promote --dir lane's arbitrary-format decoder. The
# 18.0.0 base package ships only the 44-byte-header s16 decoder (its
# FFmpegAudioService moved to the SoundFingerprinting.Emy client package),
# so the worker carries a thin CLI-backed service (src/PromoteCommand.cs).
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*
# The dotnet runtime image has no app user; uid 65532 matches the chart's
# securityContext (explicit uid + unique username — the distro username-
# collision warning in the container-creation skill).
RUN groupadd --gid 65532 aadworker \
    && useradd --uid 65532 --gid aadworker --home-dir /home/aadworker --create-home --shell /usr/sbin/nologin aadworker \
    && chown -R aadworker:aadworker /app /home/aadworker
USER aadworker
EXPOSE 8080
ENTRYPOINT ["/app/AudioAdDetection"]
