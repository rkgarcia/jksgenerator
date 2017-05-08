#!/bin/bash
DOMAIN=example.com
JKSNAME=keystore.jks
JKSPASS=myPassword
JKSDIR=/etc/tomcat7/
CERTDIR=/etc/letsencrypt/live/
KEYTOOL=/usr/bin/keytool
CERTBOT=/usr/bin/certbot
SSLCRT=$CERTDIR$DOMAIN/cert.pem
SSLKEY=$CERTDIR$DOMAIN/privkey.pem
SSLCA=$CERTDIR$DOMAIN/chain.pem
TMPNAME=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
get_days_exp() {
        local d1=$(date -d "`openssl x509 -in $1 -text -noout|grep "Not After"|cut -c 25-`" +%s)
        local d2=$(date -d "now" +%s)
        local difference=$(($d1 - $d2))
        DAYS_EXP=$((difference / 86400))
}
verifyssl() {
        local regex="^http:\/\/(.*)/$"
        local regexResp=$SSLCRT": ([a-zA-Z]*)"
        local elhash=$(openssl x509 -noout -issuer_hash -in $SSLCA)
        local ocspURL=$(openssl x509 -noout -ocsp_uri -in $SSLCRT)
        local ocspHOST=$(if [[ $ocspURL =~ $regex ]]; then thehost="${BASH_REMATCH[1]}"; echo $thehost; fi);
        local verifyResponse=$(openssl ocsp -issuer $SSLCA -cert $SSLCRT -CAfile $SSLCA -no_nonce -header Host $ocspHOST -url $ocspURL -text)
        local status=$(if [[ $verifyResponse =~ $regexResp ]]; then status="${BASH_REMATCH[1]}"; echo $status; fi);
        echo $status
}
generatekeystore() {
        echo "Creating temporal Java Keystore"
        cat $SSLCRT $SSLCA > /tmp/$TMPNAME.txt
        openssl pkcs12 -inkey $SSLKEY -in /tmp/$TMPNAME.txt -export -out /tmp/$TMPNAME.pfx -password pass:$JKSPASS
        mv /tmp/$TMPNAME.pfx $JKSDIR$JKSNAME
        chmod 777 $JKSDIR$JKSNAME
        echo "Java Keystore successully created at $JKSDIR$JKSNAME"
        echo "Deleting temporary files"
        rm /tmp/$TMPNAME.*
        /etc/init.d/tomcat7 restart
}

if [ -e $SSLCRT ]; then
        echo "Cert file exists for domain $DOMAIN"
        get_days_exp "$SSLCRT"
        statusOCSP=$(verifyssl)
        if [ "$statusOCSP" == "good" ] && [ $DAYS_EXP -gt 2 ]; then
                echo "Valid certificate";
                exit 0;
        fi
        if [ $DAYS_EXP -gt 0 ]; then
                echo "Remain $DAYS_EXP day(s)"
                if [ $DAYS_EXP -lt 3 ]; then
                        echo "Refreshing certificate"
                        certbot renew
                        generatekeystore
                fi
                exit 0;
        else
                echo "Certificate expired"
        fi
else
        echo "Creating certificate"
        certbot certonly --standalone --domain $DOMAIN
        generatekeystore
fi
