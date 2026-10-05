// Sends www.usepigeon.cc to the apex, keeping the path and query.
export default {
  fetch(request) {
    const url = new URL(request.url);
    url.hostname = "usepigeon.cc";
    return Response.redirect(url.toString(), 301);
  },
};
