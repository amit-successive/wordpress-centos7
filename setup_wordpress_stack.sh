#!/bin/bash

# Update the system
yum update -y

# Install EPEL repository
yum install epel-release -y

# Install Nginx
yum install nginx -y

# Start Nginx and enable it to start on boot
systemctl start nginx
systemctl enable nginx

# Install PHP-FPM and PHP modules
yum install https://rpms.remirepo.net/enterprise/remi-release-7.rpm -y
yum install yum-utils -y
yum-config-manager --enable remi-php81
yum install php php-fpm php-mysqlnd php-xml php-json php-gd php-mbstring php-zip -y

# Configure PHP-FPM
sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php.ini
systemctl start php-fpm
systemctl enable php-fpm

# Install MySQL server
yum install mariadb-server -y

# Start MySQL and enable it to start on boot
systemctl start mariadb
systemctl enable mariadb

# Configure MySQL
mysql_secure_installation

# Create a MySQL database and user for WordPress
read -p "Enter MySQL root password: " mysql_root_password
read -p "Enter WordPress database name: " wordpress_db_name
read -p "Enter WordPress database user: " wordpress_db_user
read -p "Enter WordPress database user password: " wordpress_db_password

mysql -uroot -p$mysql_root_password <<EOF
CREATE DATABASE $wordpress_db_name;
GRANT ALL PRIVILEGES ON $wordpress_db_name.* TO '$wordpress_db_user'@'localhost' IDENTIFIED BY '$wordpress_db_password';
FLUSH PRIVILEGES;
EXIT;
EOF

# Prompt for site name and WordPress admin details
read -p "Enter the site name: " site_name
read -p "Enter the WordPress admin username: " admin_username
read -p "Enter the WordPress admin password: " admin_password
read -p "Enter the WordPress admin email: " admin_email

# Download and configure WordPress
yum install wget -y
cd /tmp
wget https://wordpress.org/latest.tar.gz
tar xf latest.tar.gz
mv wordpress /var/www/html/$site_name
chown -R nginx:nginx /var/www/html/$site_name
chmod -R 755 /var/www/html/$site_name

# Configure Nginx virtual host
cat > /etc/nginx/conf.d/$site_name.conf <<EOF
server {
    listen 80;
    server_name $site_name;

    root /var/www/html/$site_name;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_pass unix:/run/php-fpm/www.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF

# Restart Nginx
systemctl restart nginx

# Configure WordPress
cp /var/www/html/$site_name/wp-config-sample.php /var/www/html/$site_name/wp-config.php
sed -i "s/database_name_here/$wordpress_db_name/" /var/www/html/$site_name/wp-config.php
sed -i "s/username_here/$wordpress_db_user/" /var/www/html/$site_name/wp-config.php
sed -i "s/password_here/$wordpress_db_password/" /var/www/html/$site_name/wp-config.php
sed -i "s/wp_siteurl/'http:\/\/$site_name'/" /var/www/html/$site_name/wp-config.php
sed -i "s/wp_home/'http:\/\/$site_name'/" /var/www/html/$site_name/wp-config.php

# Set up WordPress admin user
wp_cli="/usr/local/bin/wp"
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp
$wp_cli --path="/var/www/html/$site_name" core install --url="$site_name" --title="$site_name" --admin_user="$admin_username" --admin_password="$admin_password" --admin_email="$admin_email"

# Store credentials in a file
credentials_file="/root/wordpress_credentials.txt"
echo "WordPress Site: $site_name" > $credentials_file
echo "Database Name: $wordpress_db_name" >> $credentials_file
echo "Database User: $wordpress_db_user" >> $credentials_file
echo "Database Password: $wordpress_db_password" >> $credentials_file
echo "Admin Username: $admin_username" >> $credentials_file
echo "Admin Password: $admin_password" >> $credentials_file
echo "Admin Email: $admin_email" >> $credentials_file

echo "WordPress stack setup complete!"
echo "Credentials saved to: $credentials_file"
