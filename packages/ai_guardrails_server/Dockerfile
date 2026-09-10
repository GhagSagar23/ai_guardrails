FROM dart:stable AS build
WORKDIR /app

COPY pubspec.yaml .
COPY lib/ lib/
COPY packages/ packages/

RUN dart pub get
RUN dart compile exe packages/ai_guardrails_server/bin/server.dart \
    -o /app/guard_server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/guard_server /app/guard_server

EXPOSE 8080
ENTRYPOINT ["/app/guard_server"]
CMD ["/app/config.json"]
