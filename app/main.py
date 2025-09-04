from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import sqlite3
from typing import List


DB_PATH = "./db.sqlite"  # Persistencia en volumen efímero del task


app = FastAPI()


class Item(BaseModel):
    id: int | None = None
    name: str
    description: str | None = None


# Inicializar tabla
conn = sqlite3.connect(DB_PATH)
c = conn.cursor()
c.execute(
    "CREATE TABLE IF NOT EXISTS items (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, description TEXT)"
)
conn.commit()
conn.close()


@app.get("/")
def health():
    return {"status": "ok"}


@app.get("/items", response_model=List[Item])
def list_items():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    rows = conn.execute("SELECT id, name, description FROM items").fetchall()
    conn.close()
    return [Item(**dict(r)) for r in rows]


@app.post("/items", response_model=Item, status_code=201)
def create_item(item: Item):
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO items (name, description) VALUES (?, ?)",
        (item.name, item.description),
    )
    conn.commit()
    item_id = cur.lastrowid
    conn.close()
    return Item(id=item_id, name=item.name, description=item.description)


@app.get("/items/{item_id}", response_model=Item)
def get_item(item_id: int):
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    row = conn.execute(
        "SELECT id, name, description FROM items WHERE id=?", (item_id,)
    ).fetchone()
    conn.close()
    if not row:
        raise HTTPException(status_code=404, detail="Not found")
    return Item(**dict(row))


@app.put("/items/{item_id}", response_model=Item)
def update_item(item_id: int, item: Item):
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute(
        "UPDATE items SET name=?, description=? WHERE id=?",
        (item.name, item.description, item_id),
    )
    conn.commit()
    if cur.rowcount == 0:
        conn.close()
        raise HTTPException(status_code=404, detail="Not found")
    conn.close()
    return Item(id=item_id, name=item.name, description=item.description)


@app.delete("/items/{item_id}", status_code=204)
def delete_item(item_id: int):
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("DELETE FROM items WHERE id=?", (item_id,))
    conn.commit()
    conn.close()
    return


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
