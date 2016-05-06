#!/usr/bin/python

import boto3
import smtplib
import yaml
from path import path
from pprint import pprint

import sys, os


def get_config():
    pathname = "{}/config/defaults.yml".format(path(os.path.realpath(sys.argv[0])).parent.parent)
    with open(pathname) as f:
        config = yaml.load(f)
    return config

def send_alert_mail(config, msg):
    email_message = """
From: {}
To: {}
Subject: EC2 instance alert

{}

    """.format(config['mail']['from_address'], config['ec2']['instance_monitor_email'],msg)
    s = smtplib.SMTP('localhost')
    s.sendmail(config['mail']['from_address'], config['ec2']['instance_monitor_email'], msg)
    s.quit()

def main():
    error_message = ''
    config = get_config()
    ec2 = boto3.client('ec2',
        aws_access_key_id=config['ec2']['aws_access_key_id'],
        aws_secret_access_key=config['ec2']['aws_secret_access_key'],
        region_name='us-east-1'
    )
    instances = ec2.describe_instances()

    if instances['ResponseMetadata']['HTTPStatusCode'] != 200:
        error_message = "Could not read status of EC2 instances.\nHTTPStatusCode: {}".format(
            instances['ResponseMetadata']['HTTPStatusCode']
        )
    elif instances['Reservations']:
        for reservation in instances['Reservations']:
            for instance in reservation['Instances']:
                error_message = "{}instance: {} [{}] \nstate: {} \nlaunched: {}\n\n".format(
                    error_message,
                    instance['InstanceId'],
                    instance['InstanceType'],
                    instance['State']['Name'],
                    str(instance['LaunchTime'])
                )

    if len(error_message):
        send_alert_mail(config, error_message)

if __name__=="__main__":
    main()
