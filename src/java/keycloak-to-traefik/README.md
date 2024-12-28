# To build: 

## Dependencies
sudo zypper install java-17-openjdk-devel

## To compile:
export JAVA_HOME=/usr/lib64/jvm/java-17-openjdk-17
mvn clean compile package

rsync target/keycloak-to-traefik-login-listener.jar root@infra.spencerslab.com:/var/lib/rancher/k3s/storage/pvc-ccdc073d-f452-40f8-83de-dd144a31633c_default_keycloak-providers/

Then restart pod

# To use:
Set the email theme under Realm Settings > Themes > Email.
Will email all users in the Admin group. 
