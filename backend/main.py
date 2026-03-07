from fastapi import FastAPI

app = FastAPI()

@app.get("/fruit")
def list_fruit():
    return []
