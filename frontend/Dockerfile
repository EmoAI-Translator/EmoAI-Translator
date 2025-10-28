# --- Stage 1: Build Flutter web app ---
FROM debian:bookworm-slim AS build

RUN apt-get update && apt-get install -y \
    curl git unzip xz-utils zip libglu1-mesa && \
    rm -rf /var/lib/apt/lists/*

# Install Flutter SDK
RUN git clone https://github.com/flutter/flutter.git /flutter
ENV PATH="/flutter/bin:/flutter/bin/cache/dart-sdk/bin:${PATH}"

# Enable Flutter web
RUN flutter config --enable-web

WORKDIR /app
COPY frontend/ .

RUN flutter pub get
RUN flutter build web --release

# --- Stage 2: Serve via Nginx ---
FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
