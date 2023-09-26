# repo-debian

Docker solution to host your own debian packages.

## Dependencies

- gnupg2
- Install Gnupg for Windows if using WSL

## Installation

All commands are in bash. It is recommended to use WSL or a debian/ubuntu VM.

1. Copy and save the public and private keys for the debian repo. The keypair is available in the corporate password manager for the IT team under the names: admin-apt-pgp.key and admin-apt-pgp.pub

    ```bash
    cp admin-apt-pgp.key src/private/admin.key
    cp admin-apt-pgp.pub src/private/admin.gpg
    gpg --import src/private/admin.key
    ```

    *OR*

    Create the pgp key for your repository. You dont want to generate this from within the docker image as it would be overwritten each time you build a new version.

    ```bash
    gpg2 --no-tty --batch --gen-key src/pgp_key.batch
    gpg2 --armor --export admin > src/private/admin.gpg
    gpg2 --armor --export-secret-keys admin > src/private/admin.key
    ```

2. Make sure to add the keys and the private/ folder to your .gitignore file if not already done.

    ```bash
    echo -e "\nprivate/\nadmin.gpg\nadmin.key" >> .gitignore
    ```

3. Add your custom debian packages to `src/repository`.
4. Build and run the dockerfile. This must be run from the repo root.

    ```bash
    docker build -t admin-repo .
    docker run --name admin-apt-repo -p 80:80 -d admin-repo
    ```

5. On a debian/ubuntu client, set up the new repository. This guide assumes the repository server and client are on the same network already, or the server is publicly available. Update the `APT_REPO` variable with the IP/domain name and port (*if applicable*) for the repository server.

    Easiest option is to test with a docker container on the same network

    ```bash
    docker run -it --rm ubuntu:latest
    ```

    Then from the console session:

    ```bash
    APT_REPO='172.17.0.2:80'
    apt update && apt install -y curl gnupg2 && curl $APT_REPO/repo/admin.gpg | gpg --dearmor > /etc/apt/trusted.gpg.d/admin.gpg
    echo "deb http://$APT_REPO/repo stable main" > /etc/apt/sources.list.d/repo.list
    apt update && apt search xenfi
    ```
