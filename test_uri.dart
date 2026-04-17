void main() {
  var base1 = Uri.parse('https://webdav.123pan.cn/webdav');
  print('base1.resolve("/") = ${base1.resolve("/")}');
  print('base1.resolve("/folder1/") = ${base1.resolve("/folder1/")}');
  
  var base2 = Uri.parse('https://webdav.123pan.cn/webdav/');
  print('base2.resolve("/") = ${base2.resolve("/")}');
  print('base2.resolve("folder1/") = ${base2.resolve("folder1/")}');
}