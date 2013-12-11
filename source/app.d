import vibe.d;
import std.stdio;

void login(HTTPServerRequest req, HTTPServerResponse res)
{
  enforceHTTP("username" in req.form && "password" in req.form,
              HTTPStatus.badRequest, "Missing username/password field.");

  // TODO: Verify user/password here.

  auto session = res.startSession();
  session["username"] = req.form["username"];
  session["password"] = req.form["password"];
  logInfo("Logging in w/ " ~ session["username"] ~ " " ~ session["password"]);
  res.redirect("/");
}

void logout(HTTPServerRequest req, HTTPServerResponse res)
{
  res.terminateSession();
  res.redirect("/");
}

void checkLogin(HTTPServerRequest req, HTTPServerResponse res)
{
  // Redirect to "/" when the user is not authenticated.
  if (req.session is null)
    res.redirect("/");
}

void errorPage(HTTPServerRequest req,
               HTTPServerResponse res,
               HTTPServerErrorInfo error)
{
  res.render!("error.dt", req, error);
}

shared static this()
{
  auto router = new URLRouter;
  router
    // Publicly visible pages.
    .get("/", staticTemplate!"index.dt")  // Our loverly home page.
    .get("/js/*", serveStaticFiles("./public/"))  // Public files.
    .get("/css/*", serveStaticFiles("./public/"))  // Public files.
    .get("/fonts/*", serveStaticFiles("./public/"))  // Public files.
    .post("/login", &login)
    .get("/logout", &logout)
    // Force other requests through authentication.
    .any("*", &checkLogin)
    .get("/blog", staticTemplate!"blog.dt");

  auto settings = new HTTPServerSettings;
  settings.port = 8080;
  settings.bindAddresses = ["::1", "127.0.0.1"];  // Bind to any interface.
  settings.errorPageHandler = toDelegate(&errorPage);  // Custom error handling.
  settings.sessionStore = new MemorySessionStore;  // Store session data in RAM.

  listenHTTP(settings, router);

  logInfo("Please open http://127.0.0.1:8080/ in your browser.");
}
