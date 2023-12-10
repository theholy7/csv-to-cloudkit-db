# Introduction

This CLI lets a user add Location records to the public CloudKit database from a CSV.

This is just an example of the code that you should build, if you wish to do something like this.

The CSV must contain specific keys, matching with the schema of your record in CloudKit.

You can build a debug version and run it with:

```text
swift run csvToCloudKit \
    --ck-key-id "my-key-id" \
    --private-key-file-path "path/to/file.pem" \
    --csv-file-path "path/to/file.csv"
```
