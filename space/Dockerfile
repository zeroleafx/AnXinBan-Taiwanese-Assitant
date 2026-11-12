FROM python:3.11-slim
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu torch==2.8.0 && \
    pip install --no-cache-dir transformers==4.57.1 accelerate==1.10.1 fastapi==0.119.0 uvicorn==0.37.0
RUN useradd --create-home --uid 1000 app
USER app
ENV HOME=/home/app OMP_NUM_THREADS=2
WORKDIR /home/app
COPY --chown=app:app app.py .
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "7860"]
