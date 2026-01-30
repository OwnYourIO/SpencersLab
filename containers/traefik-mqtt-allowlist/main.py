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
        admin_emails = os.getenv('ADMIN_EMAILS', '')
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
            'from_email': os.getenv('FROM_EMAIL', 'allowlist@example.com'),
            'admin_emails': [email.strip() for email in admin_emails.split(',') if email.strip()],
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
            username = event.get('details', {}).get('username')
            ip_address = event.get('ipAddress')
            
            if not username or not ip_address:
                self.logger.warning("Missing username or ipAddress in event")
                return
            
            self.logger.info(f"Processing LOGIN: user={username} ip={ip_address}")
            
            result = self._update_allowlist(username, ip_address)
            
            if result['changed']:
                if result['added']:
                    self.logger.info(f"Successfully added {ip_address} for user {username}")
                    if self.config['smtp_server'] and self.config['admin_emails']:
                        self._send_notification('added', username, ip_address)
                
                if result['removed_users']:
                    for removed_user in result['removed_users']:
                        self.logger.info(f"Removed expired entry: {removed_user['ip']} for user {removed_user['username']}")
                        if self.config['smtp_server'] and self.config['admin_emails']:
                            self._send_notification('removed', removed_user['username'], removed_user['ip'], removed_user['expires'])
            else:
                self.logger.info(f"IP {ip_address} already exists in allowlist for user {username}, no changes made")
            
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
    user-allowlist:
      ipAllowList:
        sourceRange: &allowlist
          - "10.0.0.0/16"
          # START ALLOWLIST AUTOMATION
          # END ALLOWLIST AUTOMATION
    user-allowlist-remote:
      ipAllowList:
        ipStrategy:
          depth: 1
        sourceRange: *allowlist
"""
        allowlist_path.write_text(initial_content)
    
    def _update_allowlist(self, username: str, ip_address: str) -> dict:
        with self.file_lock:
            try:
                allowlist_path = Path(self.config['allowlist_file'])
                
                # Read current content
                content = allowlist_path.read_text()
                lines = content.split('\n')
                
                # Find markers
                begin_idx = None
                end_idx = None
                for i, line in enumerate(lines):
                    if 'START ALLOWLIST AUTOMATION' in line:
                        begin_idx = i
                    if 'END ALLOWLIST AUTOMATION' in line:
                        end_idx = i
                        break
                
                if begin_idx is None or end_idx is None:
                    self.logger.error("Markers not found in allowlist file")
                    return {'changed': False, 'added': False, 'removed_users': []}
                
                # Check if IP already exists
                ip_pattern = f'- "{ip_address}"'
                self.logger.info(f"Checking for existing IP pattern: {ip_pattern}")
                self.logger.info(f"Lines between markers (begin={begin_idx}, end={end_idx}): {lines[begin_idx+1:end_idx]}")
                for line in lines[begin_idx+1:end_idx]:
                    if ip_pattern in line:
                        self.logger.info(f"Found match in line: {line}")
                        return {'changed': False, 'added': False, 'removed_users': []}
                
                # Keep non-expired entries and track removed ones
                now = datetime.now()
                expiry_date = now + timedelta(days=self.config['ip_expiry_days'])
                new_section = []
                removed_users = []
                
                entry_pattern = re.compile(
                    r'- "([^"]+)" # user: ([^,]+), last-login: ([^,]+), expires: (\d{4}-\d{2}-\d{2})'
                )
                
                for line in lines[begin_idx+1:end_idx]:
                    if not line.strip():
                        continue
                    
                    match = entry_pattern.search(line)
                    if match:
                        expires = datetime.strptime(match.group(4), '%Y-%m-%d')
                        if expires < now:
                            removed_users.append({
                                'ip': match.group(1),
                                'username': match.group(2),
                                'expires': match.group(4)
                            })
                            continue
                    
                    new_section.append(line)
                
                # Add new entry with inline comment
                last_login = now.isoformat()
                expires = expiry_date.strftime('%Y-%m-%d')
                new_entry = f'          - "{ip_address}" # user: {username}, last-login: {last_login}, expires: {expires}'
                new_section.append(new_entry)
                
                # Rebuild file
                result = lines[:begin_idx+1] + new_section + lines[end_idx:]
                new_content = '\n'.join(result)
                self.logger.info(f"About to write file with {len(new_section)} entries")
                self.logger.info(f"File content to write:\n{new_content}")
                allowlist_path.write_text(new_content)
                
                # Verify write
                time.sleep(0.1)  # Small delay
                verify_content = allowlist_path.read_text()
                self.logger.info(f"Verified file content after write:\n{verify_content}")
                
                return {
                    'changed': True,
                    'added': True,
                    'removed_users': removed_users
                }
                
            except Exception as e:
                self.logger.error(f"Failed to update allowlist: {e}", exc_info=True)
                return {'changed': False, 'added': False, 'removed_users': []}
    
    def _send_notification(self, action: str, username: str, ip_address: str, expires: str = None):
        try:
            if action == 'added':
                expiry = datetime.now() + timedelta(days=self.config['ip_expiry_days'])
                subject = f"Traefik Allowlist: IP added for {username}"
                body = f"""IP Allowlist Update

Action: added
User: {username}
IP Address: {ip_address}
Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
Expires: {expiry.strftime('%Y-%m-%d')}

This IP has been automatically added to the Traefik allowlist.
"""
            elif action == 'removed':
                subject = f"Traefik Allowlist: IP removed for {username}"
                body = f"""IP Allowlist Update

Action: removed (expired)
User: {username}
IP Address: {ip_address}
Expired: {expires}
Removed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

This IP has been automatically removed from the Traefik allowlist due to expiration.
"""
            else:
                self.logger.error(f"Unknown notification action: {action}")
                return
            
            msg = MIMEText(body)
            msg['Subject'] = subject
            msg['From'] = self.config['from_email']
            
            with smtplib.SMTP(self.config['smtp_server'], self.config['smtp_port']) as server:
                if self.config['smtp_username'] and self.config['smtp_password']:
                    server.starttls()
                    server.login(self.config['smtp_username'], self.config['smtp_password'])
                
                for admin_email in self.config['admin_emails']:
                    msg['To'] = admin_email
                    server.send_message(msg)
                    self.logger.info(f"Email notification ({action}) sent to {admin_email}")
                    del msg['To']  # Remove for next iteration
            
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
