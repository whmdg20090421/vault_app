const xml2js = require('xml2js');

const xmlString = `<?xml version="1.0" encoding="UTF-8"?><D:multistatus xmlns:D="DAV:"><D:response><D:href>/webdav/</D:href><D:propstat><D:prop><D:displayname>加密</D:displayname><D:getlastmodified>Thu, 23 Apr 2026 11:07:25 GMT</D:getlastmodified><D:supportedlock><D:lockentry xmlns:D="DAV:"><D:lockscope><D:exclusive/></D:lockscope><D:locktype><D:write/></D:locktype></D:lockentry></D:supportedlock><D:resourcetype><D:collection xmlns:D="DAV:"/></D:resourcetype><D:creationdate>Thu, 23 Apr 2026 11:07:25 GMT</D:creationdate></D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response><D:response><D:href>/webdav/TF%E5%9B%BE/</D:href><D:propstat><D:prop><D:displayname>TF图</D:displayname><D:getlastmodified>Fri, 17 Apr 2026 15:47:26 GMT</D:getlastmodified><D:supportedlock><D:lockentry xmlns:D="DAV:"><D:lockscope><D:exclusive/></D:lockscope><D:locktype><D:write/></D:locktype></D:lockentry></D:supportedlock><D:resourcetype><D:collection xmlns:D="DAV:"/></D:resourcetype><D:creationdate>Fri, 17 Apr 2026 15:47:26 GMT</D:creationdate></D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response></D:multistatus>`;

xml2js.parseString(xmlString, (err, result) => {
    if (err) {
        console.error(err);
        return;
    }
    
    const responses = result['D:multistatus']['D:response'];
    const baseUrlPath = '/webdav';
    const requestedPath = '/';

    responses.forEach(response => {
        let href = decodeURIComponent(response['D:href'][0]);
        let relativePath = href;
        
        let b = baseUrlPath;
        if (b.endsWith('/')) b = b.substring(0, b.length - 1);
        
        if (b.length > 0) {
            if (relativePath === b || relativePath === b + '/') {
                relativePath = '/';
            } else if (relativePath.startsWith(b + '/')) {
                relativePath = relativePath.substring(b.length);
            }
        }
        
        if (!relativePath.startsWith('/')) {
            relativePath = '/' + relativePath;
        }

        console.log(`Href: ${href} -> Relative: ${relativePath}`);
        
        // _isSamePath mock
        function normalize(p) {
            let normalized = p.replace(/\/+/g, '/');
            if (normalized.length > 1 && normalized.endsWith('/')) {
                normalized = normalized.substring(0, normalized.length - 1);
            }
            return normalized;
        }
        
        if (normalize(relativePath) === normalize(requestedPath)) {
            console.log('  [Ignored] Same as requestedPath');
            return;
        }
        
        const pathSegments = relativePath.split('/').filter(s => s.length > 0);
        const name = pathSegments.length > 0 ? pathSegments[pathSegments.length - 1] : '';
        
        console.log(`  Name: ${name}`);
    });
});
