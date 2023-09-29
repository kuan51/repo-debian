FROM debian:stable-slim

# Source environment variables using args so that it can be easily changed based on deployment
ARG REPO_USER
ARG REPO_DOMAIN
ARG CF_API_KEY
ARG CF_EMAIL

ENV REPO_USER ${REPO_USER}
ENV REPO_DOMAIN ${REPO_DOMAIN}
ENV CF_API_KEY ${CF_API_KEY}
ENV CF_EMAIL ${CF_EMAIL}

# Set dir and create user
WORKDIR /var/www/repo
RUN useradd -ms /bin/bash $REPO_USER

# Install dependencies
RUN apt-get update && \
    apt-get install -y apache2 apache2-utils dpkg-dev apt-utils gnupg2 gpg acl curl cron

# Create repo conf and data dirs
RUN mkdir -p /opt/repo/keys && \
    mkdir -p /var/www/repo/dists/stable/main/binary-amd64 && \
    mkdir -p /var/www/repo/pool/main
# Set directory permissions and enforce inheritance
RUN chown -R $REPO_USER:$REPO_USER /opt/repo && \
    chmod u+s /opt/repo && \
    chmod g+s /opt/repo && \
    setfacl -d -m u::rwX /opt/repo && \
    setfacl -d -m g::rwX /opt/repo
# Add $REPO_USER user to www-data group
RUN usermod -a -G www-data $REPO_USER
# Copy pgp batch script
COPY ./src/pgp_key.batch /opt/repo/pgp_key.batch

# Section for using temp pgp key for signing (proof of concept), uncomment to use a new temp key for testing on each build
RUN gpg --no-tty --batch --gen-key /opt/repo/pgp_key.batch
RUN gpg --armor --export Admin > /opt/repo/keys/repo-pgp.public && \
    gpg --armor --export-secret-keys Admin > /opt/repo/keys/repo-pgp.private && \
    cp /opt/repo/keys/repo-pgp.public /var/www/repo/repo.gpg

# Section for using a repo.gpg key thats already been generated, comment in if above section for temp key is used
#COPY src/private/* /opt/repo/keys/
#RUN gpg --import /opt/repo/keys/repo.key
#RUN cat /opt/repo/keys/repo.gpg | gpg --dearmor > /etc/apt/trusted.gpg.d/repo.gpg && \
#    cp /opt/repo/keys/repo.gpg /var/www/repo/repo.gpg

# Create folder for storing deb pkgs
COPY src/repository/*.deb /var/www/repo/pool/main/
# Create Packages and Packages.gz
RUN dpkg-scanpackages pool/ > dists/stable/main/binary-amd64/Packages
RUN cat dists/stable/main/binary-amd64/Packages | gzip -9 > dists/stable/main/binary-amd64/Packages.gz && \
    apt-ftparchive release dists/stable > dists/stable/Release
# Create Release and InRelease files
RUN gpg --default-key Admin -abs -o dists/stable/Release.gpg dists/stable/Release
RUN gpg --default-key Admin --clearsign -o dists/stable/InRelease dists/stable/Release

# Configure Apache
COPY src/repo.conf /etc/apache2/sites-available/$REPO_DOMAIN.conf
COPY src/apache.conf /etc/apache2/conf-available/basic-auth.conf

# Update ServerName to match REPO_DOMAIN
RUN sed -i 's/{ServerName}/$REPO_DOMAIN/g' /etc/apache2/sites-available/$REPO_DOMAIN.conf

# Enable Apache modules, disable default page
RUN a2dissite 000-default
RUN a2ensite $REPO_DOMAIN
RUN a2enconf basic-auth
RUN a2enmod alias \
    rewrite \
    deflate \
    auth_basic \
    ssl

# Set up self signed SSL if you dont want to use ACME
RUN openssl ecparam -name secp384r1 -genkey -out /opt/repo/keys/ssl.key && \
    openssl req -new \
        -key /opt/repo/keys/ssl.key \
        -x509 \
        -nodes \
        -days 365 \
        -subj "/C=US/ST=Utah/L=Salt Lake City/O=$REPO_USER/OU=IT Operations/CN=$REPO_DOMAIN" \
        -out /opt/repo/keys/ssl.pem

# Export vars, required for some reason so that acme.sh works
# Setup ACME and replace self signed. Comment out if you want self signed only.
RUN export CF_Key=$CF_API_KEY && \
    export CF_Email=$CF_EMAIL && \
    curl https://get.acme.sh | sh -s email=it@$REPO_DOMAIN && \
    ln -s /root/.acme.sh/acme.sh /usr/local/bin/acme.sh && \
    acme.sh --upgrade --auto-upgrade && \
    # Issue cert using cloudflare plugin
    acme.sh --issue --dns dns_cf -d $REPO_DOMAIN --keylength ec-384 --apache
# Install ACME cert, overwrites the self signed cert
RUN acme.sh --install-cert -d $REPO_DOMAIN \
    --key-file /opt/repo/keys/ssl.key \
    --fullchain-file /opt/repo/keys/ssl.pem

# Set up HTTP auth with randomly generated passwd thats 20 long and base64 encoded
RUN cat /dev/urandom | \
    tr -dc 'a-zA-Z0-9-_!@#$%^&*()_+{}|:<>?=' | \
    fold -w 20 | \
    grep -i '[!@#$%^&*()_+{}|:<>?=]' | \
    head -n 1 | \
    base64 > /opt/repo/keys/htpasswd
RUN cat /opt/repo/keys/htpasswd | htpasswd -i -c /etc/apache2/.htpasswd $REPO_USER

COPY src/startup.sh /startup.sh
RUN chmod +x /startup.sh

# Changing user to $REPO_USER breaks apache for some reason
# USER $REPO_USER 

# Expose port 80 and 443
EXPOSE 80
EXPOSE 443

CMD ["/startup.sh"]
