FROM debian:stable-slim

# Set dir and create user
WORKDIR /var/www/repo
RUN useradd -ms /bin/bash repo

# Install dependencies
RUN apt-get update && \
    apt-get install -y apache2 apache2-utils dpkg-dev apt-utils gnupg2 gpg acl

# Create repo conf and data dirs
RUN mkdir -p /opt/repo/keys && \
    mkdir -p /var/www/repo/dists/stable/main/binary-amd64 && \
    mkdir -p /var/www/repo/pool/main
# Set directory permissions and enforce inheritance
RUN chown -R repo:repo /opt/repo && \
    chmod u+s /opt/repo && \
    chmod g+s /opt/repo && \
    setfacl -d -m u::rwX /opt/repo && \
    setfacl -d -m g::rwX /opt/repo
# Add repo user to www-data group
RUN usermod -a -G www-data repo
# Copy pgp batch script
COPY ./src/pgp_key.batch /opt/repo/pgp_key.batch

# Section for using temp pgp key for signing (proof of concept), uncomment to use a new temp key for testing on each build
#RUN gpg --no-tty --batch --gen-key /opt/repo/pgp_key.batch
#RUN gpg --armor --export repo > /opt/repo/keys/repo-pgp.public && \
#    gpg --armor --export-secret-keys repo > /opt/repo/keys/repo-pgp.private && \
#    cp /opt/repo/keys/repo-pgp.public /var/www/repo/repo.gpg

# Section for using a repo.gpg key thats already been generated, comment in if above section for temp key is used
COPY src/private/* /opt/repo/keys/
RUN gpg --import /opt/repo/keys/repo.key
RUN cat /opt/repo/keys/repo.gpg | gpg --dearmor > /etc/apt/trusted.gpg.d/repo.gpg && \
    cp /opt/repo/keys/repo.gpg /var/www/repo/repo.gpg

# Create folder for storing deb pkgs
COPY src/repository/*.deb /var/www/repo/pool/main/
# Create Packages and Packages.gz
RUN dpkg-scanpackages pool/ > dists/stable/main/binary-amd64/Packages
RUN cat dists/stable/main/binary-amd64/Packages | gzip -9 > dists/stable/main/binary-amd64/Packages.gz && \
    apt-ftparchive release dists/stable > dists/stable/Release
# Create Release and InRelease files
RUN gpg --default-key repo -abs -o dists/stable/Release.gpg dists/stable/Release
RUN gpg --default-key repo --clearsign -o dists/stable/InRelease dists/stable/Release

# Configure Apache
COPY src/repo.conf /etc/apache2/sites-available/repo.conf
COPY src/apache.conf /etc/apache2/conf-available/basic-auth.conf

# Enable Apache modules
RUN a2ensite repo
RUN a2enconf basic-auth
RUN a2enmod alias \
    rewrite \
    deflate \
    auth_basic \
    ssl

# Set up self signed SSL to provide some level of security for basic auth
RUN openssl ecparam -name secp384r1 -genkey -out /opt/repo/keys/ssl.key && \
    openssl req -new \
        -key /opt/repo/keys/ssl.key \
        -x509 \
        -nodes \
        -days 365 \
        -subj "/C=US/ST=Utah/L=Salt Lake City/O=repo/OU=IT Operations/CN=deb.domain.com" \
        -out /opt/repo/keys/ssl.pem

# Set up HTTP auth with randomly generated passwd thats 20 long and base64 encoded
RUN cat /dev/urandom | \
    tr -dc 'a-zA-Z0-9-_!@#$%^&*()_+{}|:<>?=' | \
    fold -w 20 | \
    grep -i '[!@#$%^&*()_+{}|:<>?=]' | \
    head -n 1 | \
    base64 > /opt/repo/keys/htpasswd
RUN cat /opt/repo/keys/htpasswd | htpasswd -i -c /etc/apache2/.htpasswd repo

COPY src/startup.sh /root/startup.sh
RUN chmod +x /root/startup.sh

# Changing user to repo breaks apache for some reason
# USER repo 

# Expose port 80 and 443
EXPOSE 80
EXPOSE 443

CMD ["/root/startup.sh"]
