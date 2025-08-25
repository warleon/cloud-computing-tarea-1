#!/usr/bin/env node
import "source-map-support/register";
import { App } from "aws-cdk-lib";
import { EcsCrudStack } from "../lib/stack";

const app = new App();
new EcsCrudStack(app, "EcsCrudStack", {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});
