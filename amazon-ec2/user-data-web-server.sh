#!/bin/bash
set -e -x

# Redirect all output to a log file
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# Update the system and install necessary packages
yum update -y
yum install -y httpd

# Start the Apache server
systemctl start httpd
systemctl enable httpd

# Fetch the Instance Metadata using IMDSv2
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
AZ=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone`
INSTANCE_ID=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id`
REGION=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region`
INSTANCE_TYPE=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type`
LOCAL_IPV4=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4`
PUBLIC_IPV4=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4`
AMI_ID=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/ami-id`
HOSTNAME=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/hostname`
MAC=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/mac`
VPC_ID=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/network/interfaces/macs/$MAC/vpc-id`
SUBNET_ID=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/network/interfaces/macs/$MAC/subnet-id`
SECURITY_GROUPS=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/security-groups`
IAM_ROLE=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/`
ACCOUNT_ID=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | grep accountId | awk -F'"' '{print $4}'`
LIFECYCLE=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-life-cycle`
if [ -z "$LIFECYCLE" ]; then LIFECYCLE="on-demand"; fi

# System Info
UPTIME=`uptime -p`
KERNEL=`uname -r`
CPU_INFO=`lscpu | grep 'Model name' | cut -f 2 -d ":" | awk '{$1=$1}1'`
MEMORY_TOTAL=`free -m | grep Mem | awk '{print $2}'`
MEMORY_USED=`free -m | grep Mem | awk '{print $3}'`
MEMORY_PERCENT=`awk "BEGIN {printf \"%.0f\", ($MEMORY_USED/$MEMORY_TOTAL)*100}"`

# Create the index.html file
cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AWS Instance Dashboard</title>
    <style>
        :root {
            --bg-gradient: linear-gradient(135deg, #0f172a 0%, #1e1b4b 100%);
            --card-bg: rgba(30, 41, 59, 0.7);
            --card-border: rgba(255, 255, 255, 0.1);
            --text-primary: #F8FAFC;
            --text-secondary: #94A3B8;
            --accent: #818CF8;
            --accent-glow: rgba(129, 140, 248, 0.5);
            --success: #4ADE80;
            --widget-bg: rgba(255, 255, 255, 0.05);
        }
        body {
            background: var(--bg-gradient);
            color: var(--text-primary);
            font-family: 'Inter', system-ui, -apple-system, sans-serif;
            min-height: 100vh;
            margin: 0;
            padding: 2rem;
            box-sizing: border-box;
            display: flex;
            justify-content: center;
            align-items: flex-start;
        }
        .dashboard {
            background: var(--card-bg);
            backdrop-filter: blur(12px);
            -webkit-backdrop-filter: blur(12px);
            border: 1px solid var(--card-border);
            border-radius: 1.5rem;
            padding: 2.5rem;
            width: 100%;
            max-width: 1000px;
            box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
        }
        
        /* Header & Widgets */
        .header-section {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 3rem;
            flex-wrap: wrap;
            gap: 1.5rem;
        }
        .title-group h1 {
            margin: 0;
            font-size: 2rem;
            font-weight: 700;
            background: linear-gradient(to right, #fff, #94a3b8);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .title-group .subtitle {
            color: var(--text-secondary);
            margin-top: 0.5rem;
            font-size: 0.9rem;
        }

        .widgets {
            display: flex;
            gap: 1rem;
        }
        .widget {
            background: var(--widget-bg);
            padding: 0.75rem 1.25rem;
            border-radius: 1rem;
            border: 1px solid var(--card-border);
            display: flex;
            align-items: center;
            gap: 0.75rem;
        }
        .status-dot {
            width: 8px;
            height: 8px;
            background-color: var(--success);
            border-radius: 50%;
            box-shadow: 0 0 10px var(--success);
            animation: pulse 2s infinite;
        }
        @keyframes pulse {
            0% { opacity: 1; }
            50% { opacity: 0.5; }
            100% { opacity: 1; }
        }
        .clock {
            font-family: 'JetBrains Mono', monospace;
            font-weight: 600;
            color: var(--accent);
        }
        
        /* Memory Bar */
        .memory-widget {
            flex-direction: column;
            align-items: flex-start;
            min-width: 140px;
        }
        .memory-label {
            font-size: 0.75rem;
            color: var(--text-secondary);
            margin-bottom: 0.25rem;
            display: flex;
            justify-content: space-between;
            width: 100%;
        }
        .progress-bar {
            width: 100%;
            height: 6px;
            background: rgba(255,255,255,0.1);
            border-radius: 3px;
            overflow: hidden;
        }
        .progress-fill {
            height: 100%;
            background: var(--accent);
            width: ${MEMORY_PERCENT}%;
            box-shadow: 0 0 10px var(--accent-glow);
        }

        /* Grid Layout */
        .grid-container {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 2rem;
        }
        .section-title {
            font-size: 0.85rem;
            text-transform: uppercase;
            letter-spacing: 0.1em;
            color: var(--accent);
            margin-bottom: 1.5rem;
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }
        .section-title::after {
            content: '';
            height: 1px;
            flex-grow: 1;
            background: linear-gradient(to right, var(--accent), transparent);
            opacity: 0.3;
        }
        
        .data-item {
            margin-bottom: 1.25rem;
        }
        .label {
            display: block;
            font-size: 0.8rem;
            color: var(--text-secondary);
            margin-bottom: 0.25rem;
        }
        .value {
            font-family: 'JetBrains Mono', monospace;
            font-size: 0.95rem;
            color: var(--text-primary);
            word-break: break-all;
            background: rgba(0,0,0,0.2);
            padding: 0.5rem;
            border-radius: 0.5rem;
            border: 1px solid transparent;
            transition: all 0.2s;
        }
        .value:hover {
            border-color: var(--accent);
            background: rgba(129, 140, 248, 0.1);
        }

        footer {
            margin-top: 4rem;
            text-align: center;
            font-size: 0.8rem;
            color: var(--text-secondary);
            opacity: 0.6;
        }
    </style>
    <script>
        function updateClock() {
            const now = new Date();
            const timeString = now.toLocaleTimeString();
            document.getElementById('clock').textContent = timeString;
        }
        setInterval(updateClock, 1000);
        window.onload = updateClock;
    </script>
</head>
<body>
    <div class="dashboard">
        <div class="header-section">
            <div class="title-group">
                <h1>Instance Dashboard</h1>
                <div class="subtitle">AWS EC2 • $REGION</div>
            </div>
            
            <div class="widgets">
                <div class="widget">
                    <div class="status-dot"></div>
                    <span style="font-size: 0.9rem; font-weight: 500;">System Online</span>
                </div>
                <div class="widget memory-widget">
                    <div class="memory-label">
                        <span>Memory</span>
                        <span>${MEMORY_PERCENT}%</span>
                    </div>
                    <div class="progress-bar">
                        <div class="progress-fill"></div>
                    </div>
                </div>
                <div class="widget">
                    <span id="clock" class="clock">--:--:--</span>
                </div>
            </div>
        </div>

        <div class="grid-container">
            <!-- Column 1 -->
            <div class="col">
                <div class="section-title">Instance Details</div>
                <div class="data-item">
                    <span class="label">Instance ID</span>
                    <div class="value">$INSTANCE_ID</div>
                </div>
                <div class="data-item">
                    <span class="label">Instance Type</span>
                    <div class="value">$INSTANCE_TYPE</div>
                </div>
                <div class="data-item">
                    <span class="label">Availability Zone</span>
                    <div class="value">$AZ</div>
                </div>
                <div class="data-item">
                    <span class="label">AMI ID</span>
                    <div class="value">$AMI_ID</div>
                </div>
                <div class="data-item">
                    <span class="label">Lifecycle</span>
                    <div class="value">$LIFECYCLE</div>
                </div>
            </div>

            <!-- Column 2 -->
            <div class="col">
                <div class="section-title">Network Configuration</div>
                <div class="data-item">
                    <span class="label">Public IP</span>
                    <div class="value">$PUBLIC_IPV4</div>
                </div>
                <div class="data-item">
                    <span class="label">Private IP</span>
                    <div class="value">$LOCAL_IPV4</div>
                </div>
                <div class="data-item">
                    <span class="label">VPC ID</span>
                    <div class="value">$VPC_ID</div>
                </div>
                <div class="data-item">
                    <span class="label">Subnet ID</span>
                    <div class="value">$SUBNET_ID</div>
                </div>
                <div class="data-item">
                    <span class="label">MAC Address</span>
                    <div class="value">$MAC</div>
                </div>
            </div>

            <!-- Column 3 -->
            <div class="col">
                <div class="section-title">System Identity</div>
                <div class="data-item">
                    <span class="label">Account ID</span>
                    <div class="value">$ACCOUNT_ID</div>
                </div>
                <div class="data-item">
                    <span class="label">IAM Role</span>
                    <div class="value">$IAM_ROLE</div>
                </div>
                <div class="data-item">
                    <span class="label">Hostname</span>
                    <div class="value">$HOSTNAME</div>
                </div>
                <div class="data-item">
                    <span class="label">Kernel Version</span>
                    <div class="value">$KERNEL</div>
                </div>
                <div class="data-item">
                    <span class="label">Uptime</span>
                    <div class="value">$UPTIME</div>
                </div>
            </div>
        </div>

        <footer>
            Generated by User Data Script • $(date)
        </footer>
    </div>
</body>
</html>
EOF

# Ensure the httpd service is correctly set up to start on boot
chkconfig httpd on