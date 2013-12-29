import vibe.d;
import vibe.utils.validation;
import core.time : dur;
import std.array;

static import util;
static import db;


void addUser(HTTPServerRequest req, HTTPServerResponse res)
{
  // Validate that user fields are good.
  validateUserName(req.form["username"], 2, 20, "_", true);
  validatePassword(req.form["password"], req.form["password_confirm"], 6, 20);
  validateEmail(req.form["email"], 60);

  // Mix the password hash with a user-specific salt.
  // This makes it difficult, even with access to the DB, to crack
  // passwords using a Rainbow Table.
  string passwordSalt = util.getRandomSalt(32);
  string passwordHash =
    generateSimplePasswordHash(req.form["password"], passwordSalt);

  logInfo("Creating user with passwordSalt=" ~ passwordSalt);
  logInfo("Creating user with passwordHash=" ~ passwordHash);
  // Stick the user into the BD.
  db.addDBUser(
            db.User(
                 req.form["username"],
                 passwordHash,
                 passwordSalt,
                 req.form["email"]));
  logInfo("User successfully created!");
  res.redirect("/");
}

void login(HTTPServerRequest req, HTTPServerResponse res)
{
  enforceHTTP("username" in req.form && "password" in req.form,
              HTTPStatus.badRequest, "Missing username/password field.");

  // Validate user input first.
  validateUserName(req.form["username"], 2, 20, "_", true);
  validateString(req.form["password"], 6, 20);

  // Verify user/password here.
  db.User user;
  if (db.findDBUser(req.form["username"], user)) {
    logInfo("Found User");
    logInfo(to!string(user));
    bool isPasswordMatch =
      testSimplePasswordHash(user.passwordHash, req.form["password"], user.passwordSalt);
    if (isPasswordMatch) {
      logInfo("Success!");
      auto session = res.startSession();
      session["username"] = user.username;
      logInfo("Logging in w/ " ~ session["username"]);
      res.redirect("/");
    }
  }
  throw new Exception("Username and password did not match!");
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

void getBlogPosts(HTTPServerRequest req, HTTPServerResponse res)
{
  db.BlogPost[] blogPosts = db.getBlogPostHeaders();
  res.render!("blog.dt", req, blogPosts);
}

void addBlogPost(HTTPServerRequest req, HTTPServerResponse res)
{
  // Create a new blog entry, redirect to the blog edit page.
  auto id = db.addBlogPost(db.BlogPost("", [], "", req.session["username"]));
  res.redirect("/blog/" ~ id.toString() ~ "/edit");
}

void viewBlogPost(HTTPServerRequest req, HTTPServerResponse res)
{
  logInfo("Viewing BlogPost " ~ req.params["_id"]);
  auto blogPost = db.getBlogPost(req.params["_id"]);
  res.render!("blogpost_view.dt", req, blogPost);
}

void editBlogPost(HTTPServerRequest req, HTTPServerResponse res)
{
  logInfo("Editing BlogPost " ~ req.params["_id"]);
  auto blogPost = db.getBlogPost(req.params["_id"]);
  res.render!("blogpost_edit.dt", req, blogPost);
}

void postBlogPost(HTTPServerRequest req, HTTPServerResponse res)
{
  logInfo("Posting BlogPost " ~ req.params["_id"]);
  auto blogPost = db.getBlogPost(req.params["_id"]);
  blogPost.title = req.form["title"];
  blogPost.tags = split(req.form["tags"]);
  blogPost.text = req.form["text"];
  db.saveBlogPost(blogPost);

  res.redirect("/blog");
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
    .post("/adduser", &addUser)
    .get("/logout", &logout)
    // Force other requests through authentication.
    .any("*", &checkLogin)
    .get("/blog", &getBlogPosts)
    .post("/blog", &addBlogPost)
    .get("/blog/:_id", &viewBlogPost)
    .get("/blog/:_id/edit", &editBlogPost)
    .post("/blog/:_id/edit", &postBlogPost);

  auto settings = new HTTPServerSettings;
  settings.port = 8443;
  settings.bindAddresses = ["::1", "127.0.0.1"];  // Bind to any interface.
  settings.keepAliveTimeout = dur!"minutes"(5);
  settings.sslContext = new SSLContext("server.crt", "server.key");
  settings.errorPageHandler = toDelegate(&errorPage);  // Custom error handling.
  settings.sessionStore = new MemorySessionStore;  // Store session data in RAM.
  settings.sslContext = new SSLContext("server.crt", "server.key");

  listenHTTP(settings, router);

  logInfo("Please open http://127.0.0.1:8443/ in your browser.");
}
