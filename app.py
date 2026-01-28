from flask import Flask
app = Flask(__name__)

@app.route('/')
def hello():
    return "<h1>Hello from ECS Fargate!</h1><p>My container is running in a private subnet.</p>"

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=80)