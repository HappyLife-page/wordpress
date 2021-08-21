# wordpress最快纯净部署 nginx+php+mysql
# 系统需求：Ubuntu20.04，18.04也可

curl -s https://raw.githubusercontent.com/HappyLife-page/wordpress/main/wordpress_installation.sh | bash -s  "你的解析好的域名"

# 说明
1. Ubuntu官方源安装所以必要和依赖的软件，如nginx，php，mysql等
2. acme申请ssl证书
3. wordpress为最新版本
4. MySQL管理员密码，ssl证书目录，wordperss源码目录，wordpress库名，用户名和密码，所有都是随机生成，最终输出到终端并保存到文档方便后续查看
