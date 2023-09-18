@echo off

rem 第三步 生成服务器端证书和客户端证书

cd "%~DP0"
mkdir keys

rem set OPENSSL_CONF=%~DP0openssl.cfg

rem 服务器端需要向 CA 机构申请签名证书，在申请签名证书之前依然是创建自己的 CSR 文件
openssl req -new -key keys\server.key -out keys\server.csr -subj /C=CN/ST=BeiJing/L=BeiJing/O=DEMO/CN=www.ssldemo.com
rem 向自己的 CA 机构申请证书，签名过程需要 CA 的证书和私钥参与，最终颁发一个带有 CA 签名的证书
openssl x509 -days 36500 -req -CA keys\ca.crt -CAkey keys\ca.key -CAcreateserial -in keys\server.csr -out keys\server.crt -extfile v3.ext

rem client 端
openssl req -new -key keys\client.key -out keys\client.csr -subj /C=CN/ST=BeiJing/L=BeiJing/O=DEMO/CN=www.ssldemo.com
rem client 端到 CA 签名
openssl x509 -days 36500 -req -CA keys\ca.crt -CAkey keys\ca.key -CAcreateserial -in keys\client.csr -out keys\client.crt -extfile v3.ext

pause