FROM debian:stable-slim

# Set dir and create user
WORKDIR /var/www/html/repo
RUN useradd -ms /bin/bash xenter

# Install dependencies
RUN apt-get update && \
    apt-get install -y apache2 apache2-utils dpkg-dev apt-utils gnupg2 gpg acl

# Create repo conf and data dirs
RUN mkdir -p /opt/repo/keys && \
    mkdir -p /var/www/html/repo/dists/stable/main/binary-amd64 && \
    mkdir -p /var/www/html/repo/pool/main
# Set directory permissions and enforce inheritance
RUN chown -R xenter:xenter /opt/repo && \
    chmod u+s /opt/repo && \
    chmod g+s /opt/repo && \
    setfacl -d -m u::rwX /opt/repo && \
    setfacl -d -m g::rwX /opt/repo
# Add xenter user to www-data group
RUN usermod -a -G www-data xenter
# Copy pgp batch script
COPY ./src/pgp_key.batch /opt/repo/pgp_key.batch

# Section for using temp pgp key for signing (proof of concept), uncomment to use a new temp key for testing on each build
#RUN gpg --no-tty --batch --gen-key /opt/repo/pgp_key.batch
#RUN gpg --armor --export Xenter > /opt/repo/keys/xenter-pgp.public && \
#    gpg --armor --export-secret-keys Xenter > /opt/repo/keys/xenter-pgp.private && \
#    cp /opt/repo/keys/xenter-pgp.public /var/www/html/repo/xenter.gpg

# Section for using a xenter.gpg key thats already been generated, comment in if above section for temp key is used
COPY src/private/* /opt/repo/keys/
RUN gpg --import /opt/repo/keys/xenter.key
RUN cat /opt/repo/keys/xenter.gpg | gpg --dearmor > /etc/apt/trusted.gpg.d/xenter.gpg && \
    cp /opt/repo/keys/xenter.gpg /var/www/html/repo/xenter.gpg && \
    chmod 600 /opt/repo/keys/* && \
    chmod 700 /opt/repo/keys

# Create folder for storing deb pkgs
COPY src/repository/*.deb /var/www/html/repo/pool/main/
# Create Packages and Packages.gz
RUN dpkg-scanpackages pool/ > dists/stable/main/binary-amd64/Packages
RUN cat dists/stable/main/binary-amd64/Packages | gzip -9 > dists/stable/main/binary-amd64/Packages.gz && \
    apt-ftparchive release dists/stable > dists/stable/Release
# Create Release and InRelease files
RUN gpg --default-key Xenter -abs -o dists/stable/Release.gpg dists/stable/Release
RUN gpg --default-key Xenter --clearsign -o dists/stable/InRelease dists/stable/Release

# Configure Apache
COPY src/apache.conf /etc/apache2/sites-available/xenter.conf
# Enable Apache modules
RUN a2ensite xenter
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
RUN cat /opt/repo/keys/htpasswd | htpasswd -i -c /etc/apache2/.htpasswd xenter

# Changing user to xenter breaks apache for some reason
# USER xenter 
EXPOSE 80
CMD ["apache2ctl", "-D", "FOREGROUND"]

# Commands for setting up repo in another docker container for testing
# docker run -it --rm ubuntu:latest
# apt update && apt install -y curl gnupg2 && curl 172.17.0.2:80/repo/xenter.gpg | gpg --dearmor > /etc/apt/trusted.gpg.d/xenter.gpg
# echo "deb http://172.17.0.2:80/repo stable main" > /etc/apt/sources.list.d/xenter.list
# apt update && apt search xenfi