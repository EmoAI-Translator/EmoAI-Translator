from pymongo import MongoClient
from dotenv import load_dotenv
import os

# 1. Call .envfile
load_dotenv()

# 2. Get DB name and URI from .envfile
MONGO_URI = os.getenv("MONGO_URI")
DB_NAME = os.getenv("DB_NAME")

# 3. Connect to MongoDB
client = MongoClient(MONGO_URI)
db = client[DB_NAME]

print("✅ MongoDB Connected Successfully:", DB_NAME)