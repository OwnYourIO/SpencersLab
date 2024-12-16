package com.keycloaktotraefik.logineventlistener.provider;

import java.util.Map;
import java.util.Map.Entry;
// SPI
import org.keycloak.events.Event;
import org.keycloak.events.EventListenerProvider;
import org.keycloak.events.admin.AdminEvent;

import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.models.UserModel;
import org.keycloak.email.EmailException;
import org.keycloak.email.EmailTemplateProvider;

// File handling.
import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class LoginEventListenerProvider implements EventListenerProvider {
    private final KeycloakSession session;

    public LoginEventListenerProvider(KeycloakSession session) {
        this.session = session;
    }

    private static final String ALLOWLIST_FILE_PATH = "/data/user-allowlist.yaml";
    private static final DateTimeFormatter TIMESTAMP_FORMATTER = DateTimeFormatter.ISO_LOCAL_DATE_TIME;
    private static final DateTimeFormatter DATE_FORMATTER = DateTimeFormatter.ISO_LOCAL_DATE;
    private static final Pattern IP_COMMENT_PATTERN = Pattern
            .compile("\"([^\"]+)\"\\s*#\\s*user:\\s*([^,]+),\\s*last-login:\\s*([^,]+),\\s*expires:\\s*([^\"]+)");

    @Override
    public void onEvent(Event event) {
        if (event.getType().toString().equals("LOGIN")) {
            try {
                // Ensure file exists before processing
                ensureAllowlistFileExists();

                // boolean isNewIp =
                RealmModel realm = this.session.realms().getRealm(event.getRealmId());
                UserModel user = this.session.users().getUserById(realm, event.getUserId());

                updateUserAllowlist(user.getUsername(), event.getIpAddress());

                // Send email if it's a new IP
                // if (isNewIp) {
                // sendNewIpNotificationEmail(event.getUserId(), event.getIpAddress());
                // }
            } catch (IOException e) {
                // Log error or handle exception as appropriate for your system
                e.printStackTrace();
            }
        }
    }

    private void ensureAllowlistFileExists() throws IOException {
        File allowlistFile = new File(ALLOWLIST_FILE_PATH);

        // If file doesn't exist, create it with default content
        if (!allowlistFile.exists()) {
            try (BufferedWriter writer = new BufferedWriter(new FileWriter(allowlistFile))) {
                writer.write("http:\n");
                writer.write("  middlewares:\n");
                writer.write("    user-allowlist:\n");
                writer.write("      ipAllowList:\n");
                writer.write("        sourceRange: &allowlist\n");
                writer.write("          # START ALLOWLIST AUTOMATION\n");
                writer.write("          # END ALLOWLIST AUTOMATION\n");
                writer.write("        ipStrategy:\n");
                writer.write("          depth: 1\n");
                writer.write("    user-allowlist-remote:\n");
                writer.write("      ipAllowList:\n");
                writer.write("        sourceRange: *allowlist\n");
            }
        }
    }

    private void updateUserAllowlist(String userId, String ipAddress) throws IOException {
        List<String> fileLines = new ArrayList<>();
        int startIndex = -1;
        int endIndex = -1;

        // Read the file
        try (BufferedReader reader = new BufferedReader(new FileReader(ALLOWLIST_FILE_PATH))) {
            String line;
            while ((line = reader.readLine()) != null) {
                fileLines.add(line);
                if (line.contains("# START ALLOWLIST AUTOMATION")) {
                    startIndex = fileLines.size() - 1;
                }
                if (line.contains("# END ALLOWLIST AUTOMATION")) {
                    endIndex = fileLines.size() - 1;
                }
            }
        }

        // Validate we found the markers
        if (startIndex == -1 || endIndex == -1) {
            throw new IOException("Could not find automation markers in the file");
        }

        // Extract the lines between markers
        List<String> allowlistLines = new ArrayList<>(fileLines.subList(startIndex + 1, endIndex));

        // Process the allowlist
        boolean modified = processAllowlist(allowlistLines, userId, ipAddress);

        // If modified, reconstruct the file
        if (modified) {
            // Replace the old allowlist section with updated lines
            fileLines.subList(startIndex + 1, endIndex).clear();
            fileLines.addAll(startIndex + 1, allowlistLines);

            // Write back to file
            try (BufferedWriter writer = new BufferedWriter(new FileWriter(ALLOWLIST_FILE_PATH))) {
                for (String line : fileLines) {
                    writer.write(line);
                    writer.newLine();
                }
            }
        }
    }

    private boolean processAllowlist(List<String> allowlistLines, String userId, String ipAddress) {
        LocalDateTime now = LocalDateTime.now();
        LocalDateTime thirtyDaysLater = now.plusDays(30);
        String formattedNow = now.format(TIMESTAMP_FORMATTER);
        String formattedExpiry = thirtyDaysLater.format(DATE_FORMATTER);

        boolean modified = false;
        boolean ipFound = false;

        // First, remove expired entries
        for (int i = 0; i < allowlistLines.size(); i++) {
            String line = allowlistLines.get(i);
            if (!line.startsWith("#")) {
                Matcher matcher = IP_COMMENT_PATTERN.matcher(line);
                if (matcher.find()) {
                    LocalDateTime expiryDate = LocalDateTime.parse(matcher.group(4), DATE_FORMATTER);
                    if (now.isAfter(expiryDate)) {
                        allowlistLines.set(i, "# " + line);
                        modified = true;
                    }
                }
            }
        }

        // Then process the current login
        for (int i = 0; i < allowlistLines.size(); i++) {
            String line = allowlistLines.get(i);

            // Check for existing IP entry
            Matcher matcher = IP_COMMENT_PATTERN.matcher(line.replaceFirst("^#*\\s*", ""));
            if (matcher.find()) {
                String existingIp = matcher.group(1);

                if (existingIp.equals(ipAddress)) {
                    ipFound = true;

                    // Check if we need to update the entry
                    String existingUser = matcher.group(2);
                    LocalDateTime lastLogin = LocalDateTime.parse(matcher.group(3), TIMESTAMP_FORMATTER);

                    // Update if different user or not today's login
                    if (!existingUser.equals(userId) ||
                            !lastLogin.toLocalDate().equals(now.toLocalDate())) {
                        // 10 spaces = 5 tabs is the needed indentation for Treafik's config.
                        String newLine = String.format("          - \"%s\" # user: %s, last-login: %s, expires: %s",
                                ipAddress, userId, formattedNow, formattedExpiry);

                        // If the line was commented out, uncomment it
                        if (line.startsWith("#")) {
                            newLine = newLine;
                        }

                        allowlistLines.set(i, newLine);
                        modified = true;
                    }
                    break;
                }
            }
        }

        // If IP not found, add a new entry
        if (!ipFound) {
            String newEntry = String.format("          - \"%s\" # user: %s, last-login: %s, expires: %s",
                    ipAddress, userId, formattedNow, formattedExpiry);
            allowlistLines.add(newEntry);
            modified = true;
        }

        return modified;
    }

    @Override
    public void onEvent(AdminEvent adminEvent, boolean b) {
        // System.out.println("Admin Event Occurred:" + toString(adminEvent));
    }

    @Override
    public void close() {
    }

    private String toString(Event event) {
        StringBuilder sb = new StringBuilder();
        sb.append("Event FOUND");
        sb.append(", type=");
        sb.append(event.getType());
        sb.append(", realmId=");
        sb.append(event.getRealmId());
        sb.append(", clientId=");
        sb.append(event.getClientId());
        sb.append(", userId=");
        sb.append(event.getUserId());
        sb.append(", ipAddress=");
        sb.append(event.getIpAddress());
        sb.append(", time=");
        sb.append(event.getTime());
        sb.append(", sessionId=");
        sb.append(event.getSessionId());
        sb.append(", details=");
        for (Map.Entry<String, String> entry : event.getDetails().entrySet()) {
            sb.append(entry.getKey() + ":" + entry.getValue().toString() + ",");
        }

        // if (event.getError() != null) {
        // sb.append(", error=");
        // sb.append(event.getError());
        // }

        if (event.getDetails() != null) {
            for (Entry<String, String> e : event.getDetails().entrySet()) {
                sb.append(", ");
                sb.append(e.getKey());
                if (e.getValue() == null || e.getValue().indexOf(' ') == -1) {
                    sb.append("=");
                    sb.append(e.getValue());
                } else {
                    sb.append("='");
                    sb.append(e.getValue());
                    sb.append("'");
                }
            }
        }

        return sb.toString();
    }

    private String toString(AdminEvent adminEvent) {
        StringBuilder sb = new StringBuilder();
        sb.append("operationType=");
        sb.append(adminEvent.getOperationType());
        sb.append(", realmId=");
        sb.append(adminEvent.getAuthDetails().getRealmId());
        sb.append(", clientId=");
        sb.append(adminEvent.getAuthDetails().getClientId());
        sb.append(", userId=");
        sb.append(adminEvent.getAuthDetails().getUserId());
        sb.append(", ipAddress=");
        sb.append(adminEvent.getAuthDetails().getIpAddress());
        sb.append(", resourcePath=");
        sb.append(adminEvent.getResourcePath());

        if (adminEvent.getError() != null) {
            sb.append(", error=");
            sb.append(adminEvent.getError());
        }

        return sb.toString();
    }
}
