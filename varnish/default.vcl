vcl 4.0;   //指定版本
import directors;   //加载后端的轮询模块
probe backend_healthcheck {   //设置名为backend_healthcheck的健康监测
    .url = "/index.html";
    .window = 5;      #窗口
    .threshold = 2;   #门槛
    .interval = 3s;
    .timeout  = 1s;
}

# 设置后端server
backend web1 { 
    .host = "192.168.30.107";
    .port = "80";
    .probe = backend_healthcheck;
}
backend web2 {
    .host = "192.168.30.7";
    .port = "80";
    .probe = backend_healthcheck;
}

# 配置后端集群事件
sub vcl_init {
    new web_cluster = directors.round_robin();   //把web1和web2 配置为轮询集群，取名为web_cluste
    web_cluster.add_backend(web1);
    web_cluster.add_backend(web2);
}
acl purgers {    # 定义可访问来源IP，权限控制
        "127.0.0.1";
        "192.168.30.0"/24;
}
sub vcl_recv {
    if (req.method == "GET" && req.http.cookie) {
        return(hash);    //处理完recv 引擎，给下一个hash引擎处理
}
   if (req.method != "GET" &&
   req.method != "HEAD" &&
   req.method != "PUT" &&
   req.method != "POST" &&
   req.method != "TRACE" &&
   req.method != "OPTIONS" &&
   req.method != "PURGE" &&
   req.method != "DELETE") {
    return (pipe);   //除了上边的请求头部，通过通道直接扔后端的pass
   }
# 定义index.php通过特殊通道给后端的server，不经过缓存
    if (req.url ~ "index.php") {
        return(pass);
    }
# 定义删除缓存的方法
    if (req.method == "PURGE") {     # PURGE请求的处理的头部，清缓存
        if (client.ip ~ purgers) {
          return(purge);
        }
    }
# 为发往后端主机的请求添加X-Forward-For首部
    if (req.http.X-Forward-For) {    # 为发往后端主机的请求添加X-Forward-For首部
        set req.http.X-Forward-For = req.http.X-Forward-For + "," + client.ip;
    } else {
        set req.http.X-Forward-For = client.ip;
    }
        return(hash);
}

# 定义vcl_hash 引擎，后没有定义hit和Miss的路径，所以走默认路径
sub vcl_hash {
     hash_data(req.url);
}

# 定义要缓存的文件时长
sub vcl_backend_response {     # 自定义缓存文件的缓存时长，即TTL值
    if (bereq.url ~ "\.(jpg|jpeg|gif|png)$") {
        set beresp.ttl = 30d;
    }
    if (bereq.url ~ "\.(html|css|js)$") {
        set beresp.ttl = 7d;
    }
    if (beresp.http.Set-Cookie) { # 定义带Set-Cookie首部的后端响应不缓存，直接返回给客户端
    set beresp.grace = 30m;  
        return(deliver);
    }
}

# 定义deliver 引擎
sub vcl_deliver {
    if (obj.hits > 0) {    # 为响应添加X-Cache首部，显示缓存是否命中
        set resp.http.X-Cache = "HIT from " + server.ip;
    } else {
        set resp.http.X-Cache = "MISS";
    }
        unset resp.http.X-Powered-By;   //取消显示php框架版本的header头
        unset resp.http.Via;   //取消显示varnish的header头
}
