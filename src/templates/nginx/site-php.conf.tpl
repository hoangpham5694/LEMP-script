server {
    listen 80;
    server_name {{SERVER_NAME}};
    root {{ROOT_DIR}};
    index index.php index.html index.htm;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_pass unix:{{PHP_SOCK}};
    }

    location ~ /\. {
        deny all;
    }
}
