#!/bin/bash

#set your servername and email here
SERVERNAME= wp
EMAIL= wp@wp.com

mkdir /wpinstall
cd /wpinstall

#generate password for mysql
SQLPASSWORD=$(date +%s|sha256sum|base64|head -c 32)
echo $SQLPASSWORD >> password.txt
debconf-set-selections <<< "mysql-server mysql-server/root_password password $SQLPASSWORD"
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $SQLPASSWORD"

# install lamp server
apt-get update
apt-get upgrade -y
apt-get -y install apache2 mysql-server php7.2 libapache2-mod-php php-mysql php-gd php-xml php-xdebug php-mbstring subversion

# set php as default
CONFIG_FILE=/etc/apache2/mods-enabled/dir.conf
SRC="index.html index.cgi index.pl index.php index.xhtml index.htm"; DST="index.php"; sed -i "s/$SRC/$DST/g" $CONFIG_FILE

# update the upload file size
SRC="upload_max_filesize = 2M"; DST="upload_max_filesize = 64M"; sed -i "s/$SRC/$DST/g" /etc/php/7.2/apache2/php.ini

# enable rewrite
a2enmod rewrite
SRC="AllowOverride None"; DST="AllowOverride All"; sed -i "s/$SRC/$DST/g" /etc/apache2/apache2.conf

# disable directory index
SRC="Options Indexes FollowSymLinks"; DST="Options -Indexes +FollowSymLinks"; sed -i "s/$SRC/$DST/g" /etc/apache2/apache2.conf

systemctl restart apache2

# download and copy wordpress to web folder
cd /wpinstall
wget http://wordpress.org/latest.tar.gz
tar xzvf latest.tar.gz
rsync -avP /wpinstall/wordpress/ /var/www/html/
touch /var/www/html/.htaccess
chown -R www-data:www-data /var/www/html/.htaccess
mkdir /var/www/html/wp-content/uploads

# remove apache default page
rm /var/www/html/index.html

# configure wordpress
CONFIG_FILE=wp-config.php
cd /var/www/html
yes | cp wp-config-sample.php $CONFIG_FILE

#generate password
PASSWORD=$(date +%s|sha256sum|base64|head -c 32)+

SRC="'WP_DEBUG', false"; DST="'WP_DEBUG', true"; sed -i "s/$SRC/$DST/g" $CONFIG_FILE
SRC="'DB_NAME', 'database_name_here'"; DST="'DB_NAME', 'wordpress'"; sed -i "s/$SRC/$DST/g" $CONFIG_FILE
SRC="'DB_USER', 'username_here'"; DST="'DB_USER', 'wordpressuser'"; sed -i "s/$SRC/$DST/g" $CONFIG_FILE
SRC="'DB_PASSWORD', 'password_here'"; DST="'DB_PASSWORD', '$PASSWORD'"; sed -i "s/$SRC/$DST/g" $CONFIG_FILE
SRC="'WP_DEBUG'"; DST="define( 'SCRIPT_DEBUG', true );"; grep -q "$DST" $CONFIG_FILE || sed -i "/$SRC/a$DST" $CONFIG_FILE

#update authentication keys and salts.
SALT=$(curl -L https://api.wordpress.org/secret-key/1.1/salt/)
SRC="define(\s*'AUTH_KEY'"; DST=$(echo $SALT|cat|grep -o define\(\'AUTH_KEY\'.\\{70\\}); sed -i "/$SRC/c$DST" $CONFIG_FILE
SRC="define(\s*'SECURE_AUTH_KEY'"; DST=$(echo $SALT|cat|grep -o define\(\'SECURE_AUTH_KEY\'.\\{70\\}); sed -i "/$SRC/c$DST" $CONFIG_FILE
SRC="define(\s*'LOGGED_IN_KEY'"; DST=$(echo $SALT|cat|grep -o define\(\'LOGGED_IN_KEY\'.\\{70\\}); sed -i "/$SRC/c$DST" $CONFIG_FILE
SRC="define(\s*'NONCE_KEY'"; DST=$(echo $SALT|cat|grep -o define\(\'NONCE_KEY\'.\\{70\\}); sed -i "/$SRC/c$DST" $CONFIG_FILE
SRC="define(\s*'AUTH_SALT'"; DST=$(echo $SALT|cat|grep -o define\(\'AUTH_SALT\'.\\{70\\}); sed -i "/$SRC/c$DST" $CONFIG_FILE
SRC="define(\s*'SECURE_AUTH_SALT'"; DST=$(echo $SALT|cat|grep -o define\(\'SECURE_AUTH_SALT\'.\\{70\\}); sed -i "/$SRC/c$DST" $CONFIG_FILE
SRC="define(\s*'LOGGED_IN_SALT'"; DST=$(echo $SALT|cat|grep -o define\(\'LOGGED_IN_SALT\'.\\{70\\}); sed -i "/$SRC/c$DST" $CONFIG_FILE
SRC="define(\s*'NONCE_SALT'"; DST=$(echo $SALT|cat|grep -o define\(\'NONCE_SALT\'.\\{70\\}); sed -i "/$SRC/c$DST" $CONFIG_FILE

# create wordpress database
mysql -uroot -p$SQLPASSWORD -e "CREATE DATABASE wordpress;"
mysql -uroot -p$SQLPASSWORD -e "CREATE USER wordpressuser@localhost IDENTIFIED BY '$PASSWORD';"
mysql -uroot -p$SQLPASSWORD -e "GRANT ALL PRIVILEGES ON wordpress.* TO wordpressuser@localhost IDENTIFIED BY '$PASSWORD';"
mysql -uroot -p$SQLPASSWORD -e "FLUSH PRIVILEGES;"

chown -R www-data:www-data /var/www/html/*

# install wp-cli
wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp --force

# install phpUnit
cd /wpinstall
wget https://phar.phpunit.de/phpunit-6.5.8.phar
chmod +x phpunit-6.5.8.phar
mv phpunit-6.5.8.phar /usr/local/bin/phpunit --force

# install PHP_CodeSniffer
wget https://squizlabs.github.io/PHP_CodeSniffer/phpcs.phar
chmod +x phpcs.phar
mv phpcs.phar /usr/local/bin/phpcs --force

wget https://squizlabs.github.io/PHP_CodeSniffer/phpcbf.phar
chmod +x phpcbf.phar
mv phpcbf.phar /usr/local/bin/phpcbf --force

# configure WordPress Coding Standards
git clone -b master https://github.com/WordPress-Coding-Standards/WordPress-Coding-Standards.git wpcs
phpcs --config-set installed_paths /wpinstall/wpcs

#install letsencrypt
echo "ServerName $SERVERNAME" >> /etc/apache2/apache2.conf
systemctl restart apache2
add-apt-repository ppa:certbot/certbot -y
apt-get update
apt-get -y install python-certbot-apache
certbot --apache -d $SERVERNAME --email=$EMAIL --agree-tos --non-interactive
