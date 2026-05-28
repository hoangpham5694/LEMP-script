server {
    listen {{PORT}};
    server_name _;

    root {{ADMINER_ROOT}};
    index index.php;

    location / {
        {{ACCESS_LINE}}
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        {{ACCESS_LINE}}
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_pass unix:{{PHP_SOCK}};
    }

    location ~ /\. {
        deny all;
    }

    auth_basic "Adminer Protected";
    auth_basic_user_file {{HTPASSWD_FILE}};
}
