FROM python:3.11
WORKDIR /app
COPY app/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY app ./app
# Ruta de la DB: /data, montada como volumen en el task (ephemeral)
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]