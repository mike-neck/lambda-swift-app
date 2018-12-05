.PHONY: compile clean resolve prepare compose zip

resolve:
	swift package resolve

clean:
	swift package clean
	rm -rf ./dist

compile:
	swift build --product bootstrap --configuration release --static-swift-stdlib

prepare:
	mkdir -p ./dist/lib

compose:
	cp ./.build/x86_64-unknown-linux/release/bootstrap ./dist/
	cp -r /usr/lib/swift/linux/* ./dist/lib
	./packaging.sh

zip:
	cd ./dist && \
	zip lambda.zip bootstrap && \
	zip -r lambda.zip lib/

build: clean compile prepare compose zip
	@echo build

release:
	aws  s3api put-object --bucket $BUCKET --key lambda.zip --body ./dist/lambda.zip
