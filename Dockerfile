FROM debian:stable-slim

# Set dir and create user
WORKDIR /var/www/html/repo
RUN useradd -ms /bin/bash admin

# Install dependencies
RUN apt-get update && \
    apt-get install -y apache2 apache2-utils dpkg-dev apt-utils gnupg2 gpg acl

# Create repo conf and data dirs
RUN mkdir -p /opt/repo/keys && \
    mkdir -p /var/www/html/repo/dists/stable/main/binary-amd64 && \
    mkdir -p /var/www/html/repo/pool/main
# Set directory permissions and enforce inheritance
RUN chown -R admin:admin /opt/repo && \
    chmod u+s /opt/repo && \
    chmod g+s /opt/repo && \
    setfacl -d -m u::rwX /opt/repo && \
    setfacl -d -m g::rwX /opt/repo
# Add admin user to www-data group
RUN usermod -a -G www-data admin
# Copy pgp batch script
COPY ./src/pgp_key.batch /opt/repo/pgp_key.batch

# Section for using temp pgp key for signing (proof of concept), uncomment to use a new temp key for testing on each build
#RUN gpg --no-tty --batch --gen-key /opt/repo/pgp_key.batch
#RUN gpg --armor --export admin > /opt/repo/keys/admin-pgp.public && \
#    gpg --armor --export-secret-keys admin > /opt/repo/keys/admin-pgp.private && \
#    cp /opt/repo/keys/admin-pgp.public /var/www/html/repo/admin.gpg

# Section for using a admin.gpg key thats already been generated, comment in if above section for temp key is used
COPY src/private/* /opt/repo/keys/
RUN gpg --import /opt/repo/keys/admin.key
RUN cat /opt/repo/keys/admin.gpg | gpg --dearmor > /etc/apt/trusted.gpg.d/admin.gpg && \
    cp /opt/repo/keys/admin.gpg /var/www/html/repo/admin.gpg && \
    chmod 600 /opt/repo/keys/* && \
    chmod 700 /opt/repo/keys

# Create folder for storing deb pkgs
COPY src/repository/*.deb /var/www/html/repo/pool/main/
# Create Packages and Packages.gz
RUN dpkg-scanpackages pool/ > dists/stable/main/binary-amd64/Packages
RUN cat dists/stable/main/binary-amd64/Packages | gzip -9 > dists/stable/main/binary-amd64/Packages.gz && \
    apt-ftparchive release dists/stable > dists/stable/Release
# Create Release and InRelease files
RUN gpg --default-key admin -abs -o dists/stable/Release.gpg dists/stable/Release
RUN gpg --default-key admin --clearsign -o dists/stable/InRelease dists/stable/Release

# Configure Apache
COPY src/apache.conf /etc/apache2/sites-available/repo.conf
# Enable Apache modules
RUN a2ensite repo
RUN a2enmod alias
RUN a2enmod rewrite
RUN a2enmod deflate

# Set up HTTP auth with randomy generated passwd thats 20 long
RUN cat /dev/urandom | \
    tr -dc 'a-zA-Z0-9-_!@#$%^&*()_+{}|:<>?=' | \
    fold -w 20 | \
    grep -i '[!@#$%^&*()_+{}|:<>?=]' | \
    head -n 1 > /opt/repo/keys/htpasswd && \
    chmod 600 /opt/repo/keys/htpasswd
RUN cat /opt/repo/keys/htpasswd | htpasswd -i -c /etc/apache2/.htpasswd admin

# Changing user to admin breaks apache for some reason
# USER admin 
EXPOSE 80
CMD ["apache2ctl", "-D", "FOREGROUND"]
