FROM dart:stable AS build
WORKDIR /app
COPY pubspec.yaml analysis_options.yaml ./
RUN dart pub get
COPY . .
RUN dart compile exe bin/server.dart -o /app/app_updater_ci

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/app_updater_ci /app/app_updater_ci
EXPOSE 8080
VOLUME /data
ENTRYPOINT ["/app/app_updater_ci", "--data", "/data"]
