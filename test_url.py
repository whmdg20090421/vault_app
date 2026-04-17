import urllib.parse
print("https://webdav.123pan.cn/webdav + / ->", urllib.parse.urljoin("https://webdav.123pan.cn/webdav", "/"))
print("https://webdav.123pan.cn/webdav + /folder1/ ->", urllib.parse.urljoin("https://webdav.123pan.cn/webdav", "/folder1/"))
print("https://webdav.123pan.cn/webdav/ + /folder1/ ->", urllib.parse.urljoin("https://webdav.123pan.cn/webdav/", "/folder1/"))
print("https://webdav.123pan.cn/webdav/ + folder1/ ->", urllib.parse.urljoin("https://webdav.123pan.cn/webdav/", "folder1/"))
