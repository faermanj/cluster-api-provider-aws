FROM jetpackio/devbox:latest

# Install Docker CLI and KIND
RUN apt-get update && apt-get install -y docker.io && \
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.26.0/kind-linux-amd64 && \
    chmod +x ./kind && mv ./kind /usr/local/bin/kind

# Set up non-root user (if needed)
RUN groupadd -g 1001 docker && usermod -aG docker vscode

# Installing your devbox project
WORKDIR /code
USER root:root
RUN mkdir -p /code && chown ${DEVBOX_USER}:${DEVBOX_USER} /code
USER ${DEVBOX_USER}:${DEVBOX_USER}
COPY --chown=${DEVBOX_USER}:${DEVBOX_USER} devbox.json devbox.json
COPY --chown=${DEVBOX_USER}:${DEVBOX_USER} devbox.lock devbox.lock



RUN devbox run -- echo "Installed Packages."

RUN devbox shellenv --init-hook >> ~/.profile
