FROM python:3.6.10-alpine

RUN pip3 install flask

COPY ./server /server
WORKDIR /server

ENTRYPOINT ["python3", "app.py"]