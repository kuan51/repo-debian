# repo-debian

Docker solution to host debian packages for the XenME and XenFi platforms.

## Dependencies

- gnupg2
- Install Gnupg for Windows if using WSL

## Installation

All commands are in bash. It is recommended to use WSL or a debian/ubuntu VM.

1. Copy and save the public and private keys for the Xenter debian repo. The keypair is available in the corporate password manager for the IT team under the names: xenter-apt-pgp.key and xenter-apt-pgp.pub

    ```bash
    cp xenter-apt-pgp.key src/private/xenter.key
    cp xenter-apt-pgp.pub src/private/xenter.gpg
    gpg --import src/private/xenter.key
    ```

    *OR*

    Create the pgp key for your repository. You dont want to generate this from within the docker image as it would be overwritten each time you build a new version.

    ```bash
    gpg2 --no-tty --batch --gen-key src/pgp_key.batch
    gpg2 --armor --export Xenter > src/private/xenter.gpg
    gpg2 --armor --export-secret-keys Xenter > src/private/xenter.key
    ```

2. Make sure to add the keys and the private/ folder to your .gitignore file if not already done.

    ```bash
    echo -e "\nprivate/\nxenter.gpg\nxenter.key" >> .gitignore
    ```

3. Build and run the dockerfile. This must be run from the repo root.

    ```bash
    docker build -t xenter-repo .
    docker run --name xenter-apt-repo -p 80:80 -d xenter-repo
    ```

4. On a debian/ubuntu client, set up the new repository. This guide assumes the repository server and client are on the same network already, or the server is publicly available. Update the `XENTER_APT_REPO` variable with the IP/domain name and port (*if applicable*) for the repository server.

    Easiest option is to test with a docker container on the same network

    ```bash
    docker run -it --rm ubuntu:latest
    ```

    Then from the console session:

    ```bash
    XENTER_APT_REPO='172.17.0.2:80'
    apt update && apt install -y curl gnupg2 && curl $XENTER_APT_REPO/repo/xenter.gpg | gpg --dearmor > /etc/apt/trusted.gpg.d/xenter.gpg
    echo "deb http://$XENTER_APT_REPO/repo stable main" > /etc/apt/sources.list.d/xenter.list
    apt update && apt search xenfi
    ```
