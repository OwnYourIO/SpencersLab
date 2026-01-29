#!/usr/bin/env python3
"""
Traefik MQTT Allowlist Manager
Listens to MQTT login events and updates Traefik allowlist dynamically.
"""

import json
import logging
import os
import re
import signal
import smtplib
import sys
import time
from datetime import datetime, timedelta
from email.mime.text import MIMEText
from pathlib import Path
from threading import Lock
from typing import Optional

import paho.mqtt.client as mqtt


class AllowlistManager:
    """Manages the Traefik IP allowlist file based on MQTT events."""
    
    def __init__(self):
        self.logger = self._setup_logging()
        self.config = self._load_config()
        self.file_lock = Lock()
        self.should_stop = False
        
        # Setup signal handlers
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)
    
    def _setup_logging(self) -> logging.Logger:
        """Configure structured logging."""
        logging.basicConfig(
            level=logging.INFO,
            format='[%(asctime)s] [%(levelname)s] %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
        return logging.getLogger('allowlist-manager')
    
    def _load_config(self) -> dict:
        """Load configuration from environment variables."""
        return {
            'mqtt_broker': os.getenv('MQTT_BROKER', 'localhost'),
            'mqtt_port': int(os.getenv('MQTT_PORT', '1883')),
            'mqtt_username': os.getenv('MQTT_USERNAME', ''),
            'mqtt_password': os.getenv('MQTT_PASSWORD', ''),
            'mqtt_topic': os.getenv('MQTT_TOPIC', 'keycloak/events/LOGIN'),
            'allowlist_file': os.getenv('ALLOWLIST_FILE', '/data/user-allowlist.yaml'),
            'ip_expiry_days': int(os.getenv('IP_EXPIRY_DAYS', '30')),
            'smtp_server': os.getenv('SMTP_SERVER', ''),
            'smtp_port': int(os.getenv('SMTP_PORT', '587')),
            'smtp_username': os.getenv('SMTP_USERNAME', ''),
            'smtp_password': os.getenv('SMTP_PASSWORD', ''),
            'admin_email': os.getenv('ADMIN_EMAIL', ''),
        }
    
    def _signal_handler(self, signum, frame):
        """Handle shutdown signals gracefully."""
        self.logger.info(f"Received signal {signum}, shutting down...")
        self.should_stop = True
    
    def _on_connect(self, client, userdata, flags, rc):
        """Callback when connected to MQTT broker."""
        if rc == 0:
            self.logger.info("Connected to MQTT broker")
            client.subscribe(self.config['mqtt_topic'], qos=1)
            self.logger.info(f"Subscribed to topic: {self.config['mqtt_topic']}")
        else:
            self.logger.error(f"Connection failed with code {rc}")
    
    def _on_disconnect(self, client, userdata, rc):
        """Callback when disconnected from MQTT broker."""
        if rc != 0:
            self.logger.warning(f"Unexpected disconnection (code {rc}), will auto-reconnect")
    
    def _on_message(self, client, userdata, msg):
        """Process incoming MQTT messages."""
        try:
            self.logger.info(f"Received message on topic {msg.topic}")
            
            # Parse JSON payload
            try:
                event = json.loads(msg.payload.decode('utf-8'))
            except json.JSONDecodeError as e:
                self.logger.error(f"Failed to parse JSON: {e}")
                self.logger.debug(f"Raw payload: {msg.payload}")
                return
            
            # Validate event type
            if event.get('type') != 'LOGIN':
                self.logger.info(f"Skipping non-LOGIN event: {event.get('type')}")
                return
            
            # Extract required fields
            username = event.get('username')
            ip_address = event.get('ipAddress')
            
            if not username or not ip_address:
                self.logger.warning("Missing username or ipAddress in event")
                return
            
            self.logger.info(f"Processing LOGIN: user={username} ip={ip_address}")
            
            # Update allowlist
            if self._update_allowlist(username, ip_address):
                self.logger.info(f"Successfully added {ip_address} for user {username}")
                
                # Send notification if configured
                if self.config['smtp_server'] and self.config['admin_email']:
                    self._send_notification(username, ip_address)
            
        except Exception as e:
            self.logger.error(f"Error processing message: {e}", exc_info=True)
    
    def _initialize_allowlist_file(self):
        """Create allowlist file if it doesn't exist."""
        allowlist_path = Path(self.config['allowlist_file'])
        
        if allowlist_path.exists():
            return
        
        self.logger.info(f"Initializing new allowlist file: {allowlist_path}")
        
        # Create directory if needed
        allowlist_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Create initial file
        initial_content = """http:
  middlewares:
    user-ip-allowlist:
      ipWhiteList:
        sourceRange:
          - "127.0.0.1/32"
# BEGIN AUTOMATED ALLOWLIST - DO NOT EDIT BELOW THIS LINE
# END AUTOMATED ALLOWLIST
"""
        allowlist_path.write_text(initial_content)
    
    def _update_allowlist(self, username: str, ip_address: str) -> bool:
        """Update the allowlist file with a new IP address."""
        with self.file_lock:
            try:
                allowlist_path = Path(self.config['allowlist_file'])
                
                # Read current content
                content = allowlist_path.read_text()
                lines = content.split('\n')
                
                # Find markers
                try:
                    begin_idx = next(i for i, line in enumerate(lines) 
                                    if 'BEGIN AUTOMATED ALLOWLIST' in line)
                    end_idx = next(i for i, line in enumerate(lines) 
                                  if 'END AUTOMATED ALLOWLIST' in line)
                except StopIteration:
                    self.logger.error("Markers not found in allowlist file")
                    return False
                
                # Check if IP already exists
                ip_entry = f'"{ip_address}/32"'
                for i in range(begin_idx + 1, end_idx):
                    if ip_entry in lines[i]:
                        self.logger.info(f"IP {ip_address} already exists in allowlist")
                        return True
                
                # Remove expired entries
                now = datetime.now()
                expiry_date = now + timedelta(days=self.config['ip_expiry_days'])
                new_section = []
                
                comment_pattern = re.compile(
                    r'# Added: (\d{4}-\d{2}-\d{2}) User: (.+) Expires: (\d{4}-\d{2}-\d{2})'
                )
                
                i = begin_idx + 1
                while i < end_idx:
                    line = lines[i]
                    
                    if not line.strip():
                        i += 1
                        continue
                    
                    # Check if it's a comment with expiry date
                    match = comment_pattern.search(line)
                    if match:
                        expires_str = match.group(3)
                        expires = datetime.strptime(expires_str, '%Y-%m-%d')
                        
                        if expires < now:
                            self.logger.info(f"Removing expired entry: {match.group(2)}")
                            i += 2  # Skip comment and IP line
                            continue
                    
                    new_section.append(line)
                    i += 1
                
                # Add new entry
                comment = (f'          # Added: {now.strftime("%Y-%m-%d")} '
                          f'User: {username} Expires: {expiry_date.strftime("%Y-%m-%d")}')
                ip_line = f'          - "{ip_address}/32"'
                new_section.extend([comment, ip_line])
                
                # Rebuild file
                result = lines[:begin_idx+1] + new_section + lines[end_idx:]
                
                # Write back
                allowlist_path.write_text('\n'.join(result))
                
                return True
                
            except Exception as e:
                self.logger.error(f"Failed to update allowlist: {e}", exc_info=True)
                return False
    
    def _send_notification(self, username: str, ip_address: str):
        """Send email notification about allowlist update."""
        try:
            expiry = datetime.now() + timedelta(days=self.config['ip_expiry_days'])
            
            msg = MIMEText(f"""IP Allowlist Update

Action: added
User: {username}
IP Address: {ip_address}
Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
Expires: {expiry.strftime('%Y-%m-%d')}

This IP has been automatically added to the Traefik allowlist.
""")
            
            msg['Subject'] = f"Traefik Allowlist: IP added for {username}"
            msg['From'] = self.config['smtp_username']
            msg['To'] = self.config['admin_email']
            
            with smtplib.SMTP(self.config['smtp_server'], self.config['smtp_port']) as server:
                server.starttls()
                server.login(self.config['smtp_username'], self.config['smtp_password'])
                server.send_message(msg)
            
            self.logger.info(f"Email notification sent to {self.config['admin_email']}")
            
        except Exception as e:
            self.logger.warning(f"Failed to send email notification: {e}")
    
    def run(self):
        """Start the MQTT client and run the main loop."""
        self.logger.info("Starting MQTT Allowlist Manager")
        self.logger.info(f"MQTT Broker: {self.config['mqtt_broker']}:{self.config['mqtt_port']}")
        self.logger.info(f"Subscribing to: {self.config['mqtt_topic']}")
        
        # Initialize allowlist file
        self._initialize_allowlist_file()
        
        # Setup MQTT client
        client = mqtt.Client(client_id="traefik-allowlist-manager", clean_session=True)
        
        # Set callbacks
        client.on_connect = self._on_connect
        client.on_disconnect = self._on_disconnect
        client.on_message = self._on_message
        
        # Set credentials if provided
        if self.config['mqtt_username']:
            client.username_pw_set(
                self.config['mqtt_username'],
                self.config['mqtt_password']
            )
        
        # Connect to broker
        try:
            client.connect(
                self.config['mqtt_broker'],
                self.config['mqtt_port'],
                keepalive=60
            )
        except Exception as e:
            self.logger.error(f"Failed to connect to MQTT broker: {e}")
            sys.exit(1)
        
        # Start network loop in background thread
        client.loop_start()
        
        # Keep running until shutdown signal
        try:
            while not self.should_stop:
                time.sleep(1)
        except KeyboardInterrupt:
            self.logger.info("Interrupted by user")
        
        # Cleanup
        self.logger.info("Disconnecting from MQTT broker...")
        client.loop_stop()
        client.disconnect()
        self.logger.info("Shutdown complete")


if __name__ == '__main__':
    manager = AllowlistManager()
    manager.run()
