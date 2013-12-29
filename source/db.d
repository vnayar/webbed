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

BsonObjectID addDBUser(User user)
{
  user._id = BsonObjectID.generate();
  // Insert the data into the "users" collection of the database.
  auto users = db["users"];
  users.insert(serializeToBson!User(user));
  return user._id;
}

bool findDBUser(in string username, out User user)
{
  auto users = db["users"];
  Bson userBson = users.findOne(["username": username]);
  if (!userBson.isNull()) {
    user = deserializeBson!User(userBson);
    return true;
  }
  return false;
}

struct BlogPost
{
  string title;
  string[] tags;
  @optional string text;
  string username;
  @optional BsonObjectID user;

  BsonObjectID _id;
}

BsonObjectID addBlogPost(BlogPost blogPost)
{
  blogPost._id = BsonObjectID.generate();
  auto blogPostsCollection = db["blogposts"];
  // Insert a new blog post.
  blogPostsCollection.insert(serializeToBson(blogPost));
  return blogPost._id;
}

void saveBlogPost(BlogPost blogPost)
{
  auto blogPostsCollection = db["blogposts"];
  logInfo("About to save blogpost with " ~ blogPost._id.toString());
  blogPostsCollection.update(["_id" : blogPost._id], serializeToBson(blogPost));
}

BlogPost getBlogPost(string id)
{
  auto blogPostsCollection = db["blogposts"];
  logInfo("About to get blogpost");
  Bson blogPostBson = blogPostsCollection.findOne(["_id" : BsonObjectID.fromString(id)]);
  if (blogPostBson.isNull())
    throw new Exception("Could not find blogpost with _id = " ~ id);
  logInfo("About to deserialize " ~ blogPostBson.toJson().toString());
  BlogPost blogPost = deserializeBson!BlogPost(blogPostBson);
  logInfo("Got blogpost");
  return blogPost;
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
    BlogPost blogPost = deserializeBson!BlogPost(bson);
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
