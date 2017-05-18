@echo off

rem 第一步 为服务器端和客户端准备公钥、私钥

cd "%~DP0"
mkdir keys

set OPENSSL_CONF=%~DP0openssl.cfg

rem 生成服务器端私钥
openssl genrsa -out keys\server.key 2048
rem 生成服务器端公钥
openssl rsa -in keys\server.key -pubout -out keys\server.pem


rem 生成客户端私钥
openssl genrsa -out keys\client.key 2048
rem 生成客户端公钥
openssl rsa -in keys\client.key -pubout -out keys\client.pem

pause