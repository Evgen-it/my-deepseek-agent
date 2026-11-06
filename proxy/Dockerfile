FROM python:3.12-slim

WORKDIR /app

# Копируем только исходники прокси
COPY proxy.py requirements.txt ./

RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 9526

CMD ["uvicorn", "proxy:app", "--host", "0.0.0.0", "--port", "9526"]