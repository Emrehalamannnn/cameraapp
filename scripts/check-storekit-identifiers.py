#!/usr/bin/env python3
"""Keeps the StoreKit configuration in step with the app's product identifiers.

Nothing in the build catches a rename on one side of that pairing: the app
simply finds no products, the paywall silently falls back to its own prices,
and every purchase fails with "isn't available yet".
"""
import json
import re
import sys

PLAN = "CameraApp/Subscription/SubscriptionPlan.swift"
CONFIG = "StoreKit/CameraApp.storekit"

source = open(PLAN, encoding="utf-8").read()
in_source = set(re.findall(r'return "([\w.]+\.pro\.[\w]+)"', source))

config = json.load(open(CONFIG, encoding="utf-8"))
in_config = {
    subscription["productID"]
    for group in config["subscriptionGroups"]
    for subscription in group["subscriptions"]
}

if not in_source:
    sys.exit(f"No product identifiers found in {PLAN} — has the format changed?")

if in_source != in_config:
    print(f"{PLAN}:      {sorted(in_source)}")
    print(f"{CONFIG}: {sorted(in_config)}")
    sys.exit("Product identifiers differ between the app and the StoreKit configuration.")

print(f"Product identifiers match ({len(in_source)}): {sorted(in_source)}")
