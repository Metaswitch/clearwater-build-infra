#!/usr/bin/env python3

import argparse
import os
import sys
import uuid
import subprocess
from time import sleep

parser = argparse.ArgumentParser(description='Run a service test in Docker')
parser.add_argument('service_test_dir',
                    type=str,
                    help='Path of the service test directory')

args = parser.parse_args()

absolute_dir = os.path.abspath(args.service_test_dir)
log_dir = os.path.join(absolute_dir, "log")

if not os.path.exists(args.service_test_dir):
    print("No service tests found")
    sys.exit(0)

# Generate unique IDs for our image and container, so we can delete them after the test
docker_image_id = str(uuid.uuid4())
docker_container_name = str(uuid.uuid4())

# We don't want to delete the image we're building now at the end of this test,
# though - Docker caches intermediate images, which makes subsequent builds
# faster, and deleting the image after every test run also deletes the cached
# intermediate images and slows down tests.
#
# Instead, we save off the image ID to a file, and each build deletes the
# _previous_ image - but only after building a new image, which keeps
# intermediate images in the cache.
#
# This isn't perfect cleanup - if someone does a test and then never works on
# that repo again, they'll have an image which will never get deleted.
# Likewise, it's possible to delete or lose track of the
# service_tests/previous_image_id file.
old_image_id_path = os.path.join(args.service_test_dir, "previous_image_id")
old_image_id = None

if os.path.exists(old_image_id_path):
    with open(old_image_id_path) as f:
        old_image_id = f.read().strip()

with open(old_image_id_path, "w") as f:
    f.write(docker_image_id)

try:
    os.chdir(args.service_test_dir)
    subprocess.check_call(["docker", "build", "-t", docker_image_id, "."])
    subprocess.check_call(["docker", "run",
                           "--name", docker_container_name,
                           "-v", "{}:/log".format(log_dir),
                           "-t", docker_image_id])
finally:
    # Delete the container we just built.
    subprocess.check_call(["docker", "rm", docker_container_name])
    # Delete the _previous_ image, not the one we just built.
    if old_image_id is not None:
        subprocess.check_call(["docker", "rmi", old_image_id])
