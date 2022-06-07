# Explicitly specify `focal` because `swift:latest` does not use `ubuntu:latest`.
ARG BUILDER_IMAGE=swift:focal
ARG RUNTIME_IMAGE=ubuntu:20.04
ARG SWIFTLINT_REVISION=0.47.1
ARG SWIFT_FORMAT_REVISION=0.49.7

#builder base image
FROM ${BUILDER_IMAGE} AS builder-base
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libxml2-dev \
    && rm -r /var/lib/apt/lists/*

# builder image -> SwiftLint
FROM builder-base AS builder-swiftlint

WORKDIR /workdir/

RUN git clone https://github.com/realm/SwiftLint.git .
RUN git checkout -f -q ${SWIFTLINT_REVISION}

RUN ln -s /usr/lib/swift/_InternalSwiftSyntaxParser .

ARG SWIFT_FLAGS="-c release -Xswiftc -static-stdlib -Xlinker -lCFURLSessionInterface -Xlinker -lCFXMLInterface -Xlinker -lcurl -Xlinker -lxml2 -Xswiftc -I. -Xlinker -fuse-ld=lld -Xlinker -L/usr/lib/swift/linux"
RUN swift build $SWIFT_FLAGS
RUN mkdir -p /executables
RUN for executable in $(swift package completion-tool list-executables); do \
        install -v `swift build $SWIFT_FLAGS --show-bin-path`/$executable /executables; \
    done

# builder image -> SwiftFormat
FROM builder-base AS builder-swiftformat

WORKDIR /workdir/

RUN git clone https://github.com/nicklockwood/SwiftFormat.git .
RUN git checkout -f -q ${SWIFT_FORMAT_REVISION}

RUN ln -s /usr/lib/swift/_InternalSwiftSyntaxParser .

ARG SWIFT_FLAGS="-c release -Xswiftc -static-stdlib -Xlinker -lCFURLSessionInterface -Xlinker -lCFXMLInterface -Xlinker -lcurl -Xlinker -lxml2 -Xswiftc -I. -Xlinker -fuse-ld=lld -Xlinker -L/usr/lib/swift/linux"
RUN swift build $SWIFT_FLAGS
RUN mkdir -p /executables
RUN SWIFTFORMAT_BIN_PATH=`swift build --configuration release --show-bin-path` && \
    mv $SWIFTFORMAT_BIN_PATH/swiftformat /executables/swiftformat


# runtime image
FROM ${RUNTIME_IMAGE}
LABEL org.opencontainers.image.source https://github.com/realm/SwiftLint
RUN apt-get update && apt-get install -y \
    libcurl4 \
    libxml2 \
 && rm -r /var/lib/apt/lists/*
COPY --from=builder-swiftlint /usr/lib/libsourcekitdInProc.so /usr/lib
COPY --from=builder-swiftlint /usr/lib/swift/linux/libBlocksRuntime.so /usr/lib
COPY --from=builder-swiftlint /usr/lib/swift/linux/libdispatch.so /usr/lib
COPY --from=builder-swiftlint /usr/lib/swift/linux/lib_InternalSwiftSyntaxParser.so /usr/lib
COPY --from=builder-swiftlint /executables/* /usr/bin
COPY --from=builder-swiftformat /executables/* /usr/bin

RUN swiftlint version
RUN swiftformat --version