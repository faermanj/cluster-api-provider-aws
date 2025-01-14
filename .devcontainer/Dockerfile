FROM jetpackio/devbox:latest

USER root:root
RUN apt-get update && apt-get install -y docker.io && \
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.26.0/kind-linux-amd64 && \
    chmod +x ./kind && mv ./kind /usr/local/bin/kind

RUN groupadd -g 1001 docker && usermod -aG docker vscode
WORKDIR /code
RUN mkdir -p /code && chown ${DEVBOX_USER}:${DEVBOX_USER} /code

USER ${DEVBOX_USER}:${DEVBOX_USER}
COPY --chown=${DEVBOX_USER}:${DEVBOX_USER} devbox.json devbox.json
COPY --chown=${DEVBOX_USER}:${DEVBOX_USER} devbox.lock devbox.lock
RUN devbox run -- echo "Installed Packages."
RUN devbox shellenv --init-hook >> ~/.profile
