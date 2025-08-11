FROM node:20-alpine
WORKDIR /app

# Tambah tools yang dibutuhkan saat install
RUN apk add --no-cache git wget

# Salin hanya package.json dulu (hindari lock lama)
COPY package.json ./
# (opsi 1) tanpa lockfile:
RUN npm install --omit=dev
# (opsi 2) kalau kamu MAU pakai lockfile yang baru, lihat catatan di bawah

# Baru salin seluruh source
COPY . .
EXPOSE 3000
CMD ["npm", "start"]
