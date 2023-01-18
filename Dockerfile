FROM wordpress:latest
COPY entrypoint.sh .

# Enable SSH server compatible with App Service
RUN apt update && \
    apt install -y --no-install-recommends dialog openssh-server && \
    echo "root:Docker!" | chpasswd && \
    chmod u+x ./entrypoint.sh

COPY sshd_config /etc/ssh

EXPOSE 2222

ENTRYPOINT [ "./entrypoint.sh" ]