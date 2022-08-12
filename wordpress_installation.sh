#!/bin/bash
# Auth: happylife
# Desc: wordpress installation script
# Plat: ubuntu 18.04 20.04
# Eg  : bash wordpress_installation.sh "你的域名"

# 使用Ubuntu官方源安装nginx php mysql和一些依赖，关闭防火墙ufw
apt install nginx php php-fpm php-opcache php-mysql php-gd php-xmlrpc php-imagick php-mbstring php-zip php-json php-mbstring php-curl php-xml mariadb-server memcached php-memcached php-memcache -y
ufw disable


# 定义域名,MySQL和wordpress(以下简称wp)需要用的参数
#0.设置你的解析好的域名
wp_domainName="$1"

#1.随机生成MySQL的root用户密码
mysql_root_pwd="`pwgen 8 1`"

#2.随机生成wp用户名
wp_user_name="`pwgen -0 8 1`"

#3.随机生成wp密码
wp_user_pwd="$(pwgen -cny -r "\"\\;'\`" 26 1)"

#4.随机生成wp数据库名
wp_db_name="`pwgen -A0 9 1`"

#5.随机生成并创建wp源码目录
wp_code_dir="$(mkdir -pv "/`pwgen -A0 8 3 | xargs |sed 's/ /\//g'`" |awk -F"'" END'{print $2}')"

#6.以时间为基准随机创建一个存放ssl证书的目录
ssl_dir="$(mkdir -pv "${wp_code_dir}/ssl/`date +"%F-%H-%M-%S"`" |awk -F"'" END'{print $2}')"


# 执行mysql_secure_installation命令优化MySQL配置
# 包括设置root密码,移除匿名用户,禁用root账户远程登陆,删除测试库,和重载权限表使优化生效
/usr/bin/expect <<-EOCCCCCC
spawn /usr/bin/mysql_secure_installation
expect "Enter current password for root (enter for none):"
send "\r"
expect "Set root password? "
send "Y\r"
expect "New password: "
send "${mysql_root_pwd}\r"
expect "Re-enter new password: "
send "${mysql_root_pwd}\r"
expect "Remove anonymous users?"
send "Y\r"
expect "Disallow root login remotely?"
send "Y\r"
expect "Remove test database and access to it?"
send "Y\r"
expect "Reload privilege tables now?"
send "Y\r"
expect eocccccc;
EOCCCCCC


# 下载wp,创建wp库,设置wp用户名和密码并设置访问权限
#1.下载wp最新源码,并解压到wp目录
curl https://wordpress.org/latest.tar.gz | tar xz -C ${wp_code_dir}

#2.授权nginx用户访问wp源码目录
chown -R www-data.www-data ${wp_code_dir}

#3.创建wp库,给wp设置MySQL用户名和密码并授予访问权限
mysql -uroot -p${mysql_root_pwd} <<-EOC
#3.1 创建wp数据库
create database ${wp_db_name};
#3.2 创建wp用户并设置密码
create user ${wp_user_name}@'localhost' identified by "${wp_user_pwd}";
#3.3 授权wp用户访问wp库
grant all privileges on ${wp_db_name}.* to ${wp_user_name}@'localhost';
#3.4 刷新权限使其生效
flush privileges;
EOC


# 安装acme,并申请加密证书
source ~/.bashrc
if nc -z localhost 443;then /etc/init.d/nginx stop;fi
if ! [ -d /root/.acme.sh ];then curl https://get.acme.sh | sh;fi
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh --issue -d "$wp_domainName" -k ec-256 --alpn
~/.acme.sh/acme.sh --installcert -d "$wp_domainName" --fullchainpath $ssl_dir/${wp_domainName}.crt --keypath $ssl_dir/${wp_domainName}.key --ecc
chown www-data.www-data $ssl_dir/*


## 把申请证书命令添加到计划任务
if ! grep -q '/usr/local/bin/ssl_renew.sh' /var/spool/cron/crontabs/root;then
echo -n '#!/bin/bash
/etc/init.d/nginx stop
wait;"/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" &> /root/renew_ssl.log
wait;/etc/init.d/nginx start
' > /usr/local/bin/ssl_renew.sh
chmod +x /usr/local/bin/ssl_renew.sh
(crontab -l;echo "15 03 * * * /usr/local/bin/ssl_renew.sh") | crontab
fi


# 给wp添加nginx配置文件
echo "
server {
   	listen 80;
	server_name $wp_domainName;
        return 301 https://"'$host$request_uri'";
}
server {
        # SSL configuration
        listen 443 ssl http2;
        listen [::]:443 ssl http2;
        server_name $wp_domainName;
        ssl_certificate $ssl_dir/${wp_domainName}.crt;
        ssl_certificate_key $ssl_dir/${wp_domainName}.key;
        ssl_ciphers EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+ECDSA+AES128:EECDH+aRSA+AES128:RSA+AES128:EECDH+ECDSA+AES256:EECDH+aRSA+AES256:RSA+AES256:EECDH+ECDSA+3DES:EECDH+aRSA+3DES:RSA+3DES:!MD5;
	ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;

        access_log /var/log/nginx/$wp_domainName.access.log;
        error_log /var/log/nginx/$wp_domainName.error.log;

        root ${wp_code_dir}/wordpress;
        index index.php;

        "'location / {
           try_files $uri $uri/ /index.php$is_args$args;
        }

        location ~ \.php$ {
            try_files $uri =404;
            fastcgi_split_path_info ^(.+\.php)(/.+)$;
            fastcgi_pass unix:/run/php/php-fpm.sock;
            fastcgi_index index.php;
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            fastcgi_param PATH_INFO $fastcgi_path_info;
        }

        location = /xmlrpc.php {
            deny all;
            access_log off;
        }

        location = /favicon.ico {
            log_not_found off;
            access_log off;
        }

        location = /robots.txt {
            allow all;
            log_not_found off;
            access_log off;
        }

        location ~ /\. {
            deny all;
        }

        location ~* /(?:uploads|files)/.*\.php$ {
            deny all;
        }

        location ~* \.(js|css|png|jpg|jpeg|gif|ico)$ {
            expires max;
            log_not_found off;
        }'"
    }
" > /etc/nginx/conf.d/wordpress.conf


# 配置php
ln -s /run/php/php*.sock /run/php/php-fpm.sock
ln -s /etc/init.d/php*-fpm /etc/init.d/php-fpm 

# 删除apache并清理其依赖包
/etc/init.d/apache2 stop
apt purge apache2 -y && apt autoremove -y
# 重启php和nginx
/etc/init.d/php-fpm start
/etc/init.d/nginx restart

# 输出配置信息
#wp安装配置信息文件
wp_ins_info="/root/wp_installation_info.txt"
echo "
你的域名	: $wp_domainName
MySQL root密码	: $mysql_root_pwd
wp库名		: $wp_db_name
wp用户名	: $wp_user_name
wp密码		: $wp_user_pwd
wp源码目录	: $wp_code_dir
ssl证书目录	: $ssl_dir
" | tee $wp_ins_info
