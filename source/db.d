import vibe.core.log;
import vibe.db.mongo.mongo;


/** Client connection to the MongoDB database. */
MongoClient client;

/** The specific database for the 'webbed' application. */
MongoDatabase db;


struct User
{
  string username;
  string passwordHash;
  string passwordSalt;
  string email;

  BsonObjectID _id;
}

void addDBUser(in User user)
{
  // Insert the data into the "users" collection of the database.
  auto users = db["users"];
  users.insert(["username" : user.username,
                "password_hash" : user.passwordHash,
                "password_salt" : user.passwordSalt,
                "email" : user.email
                ]);
}

bool findDBUser(in string username, out User user)
{
  auto users = db["users"];
  Bson userBson = users.findOne(["username": username]);
  if (!userBson.isNull()) {
    user = User(userBson["username"].get!string(),
                userBson["password_hash"].get!string(),
                userBson["password_salt"].get!string(),
                userBson["email"].get!string(),
                userBson["_id"].get!BsonObjectID()
                );
    return true;
  }
  return false;
}

struct BlogPost
{
  string title;
  string[] tags;
  string text;
  BsonObjectID user;

  BsonObjectID _id;
}

BlogPost[] getBlogPostHeaders()
{
  auto blogpostsCollection = db["blogposts"];
  // Get the posts but leave out the text.
  MongoCursor blogPostsCursor = blogpostsCollection.find(Bson.EmptyObject, ["text": 0]);

  // Start assembling our data.
  BlogPost[] blogPosts;
  for (auto i=0; i < 10 && !blogPostsCursor.empty(); i++) {
    Bson bson = blogPostsCursor.front();
    BlogPost blogPost = BlogPost();
    blogPost.title = bson["title"].get!string();
    foreach (tagBson; bson["tags"].get!(Bson[])()) {
      blogPost.tags ~= tagBson.get!string();
    }
    blogPost._id = bson["_id"].get!BsonObjectID();
    blogPosts ~= blogPost;
    blogPostsCursor.popFront();
  }

  return blogPosts;
}

shared static this()
{
  // Initialize a connection to the MongoDB server.
  logInfo("Connecting to MongoDB.");

  client = connectMongoDB("127.0.0.1");
  db = client.getDatabase("webbed");
}
