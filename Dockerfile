FROM debian:latest
WORKDIR /lua4mqtt
RUN apt update
RUN apt install -y lua5.3 lua5.3-dev git luarocks lua-json libmosquitto-dev libssl-dev build-essential
RUN luarocks install lua-mosquitto 0.3-1
RUN luarocks install luafilesystem
RUN luarocks install cqueues CRYPTO_LIBDIR=/usr/lib/arm-linux-gnueabihf OPENSSL_LIBDIR=/usr/lib/arm-linux-gnueabihf
COPY lua4mqtt.lua .
CMD ["./lua4mqtt.lua"]
