import vibe.d;
import vibe.utils.validation;
import std.random : uniform;
import core.time : dur;


MongoClient client;
MongoDatabase db;

string randomSalt(int length)
{
  string saltCharSet =
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  char[] salt;
  salt.length = length;
  foreach (i; 0 .. length) {
    salt[i] = saltCharSet[uniform(0, saltCharSet.length)];
  }
  return salt.idup;
}

void addUser(HTTPServerRequest req, HTTPServerResponse res)
{
  // Validate that user fields are good.
  validateUserName(req.form["username"], 2, 20, "_", true);
  validatePassword(req.form["password"], req.form["password_confirm"], 6, 20);
  validateEmail(req.form["email"], 60);

  // Mix the password hash with a user-specific salt.
  // This makes it difficult, even with access to the DB, to crack
  // passwords using a Rainbow Table.
  string passwordSalt = randomSalt(32);
  string passwordHash =
    generateSimplePasswordHash(req.form["password"], passwordSalt);

  logInfo("Creating user with passwordSalt=" ~ passwordSalt);
  logInfo("Creating user with passwordHash=" ~ passwordHash);
  // Insert the data into the "users" collection of the database.
  auto users = db["users"];
  users.insert(["username" : req.form["username"],
                "password_hash" : passwordHash,
                "password_salt" : passwordSalt,
                "email" : req.form["email"]
                ]);
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
  auto users = db["users"];
  Bson user = users.findOne(["username": req.form["username"]]);
  logInfo("Found User");
  if (!user.isNull()) {
    logInfo("Found User");
    string passwordSalt = user["password_salt"].get!string();
    string passwordHash = user["password_hash"].get!string();
    bool isPasswordMatch =
      testSimplePasswordHash(passwordHash, req.form["password"], passwordSalt);
    if (isPasswordMatch) {
      logInfo("Success!");
      auto session = res.startSession();
      session["username"] = req.form["username"];
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

shared static this()
{
  // Initialize a connection to the MongoDB server.
  logInfo("Connecting to MongoDB.");
  client = connectMongoDB("127.0.0.1");
  db = client.getDatabase("webbed");

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
    .get("/blog", staticTemplate!"blog.dt");

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
