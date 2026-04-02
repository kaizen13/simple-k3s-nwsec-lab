FROM node:18-alpine

WORKDIR /app

RUN npm install express redis

COPY script.js .

CMD ["node", "script.js"]