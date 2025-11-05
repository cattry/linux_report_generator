#!/bin/bash
# sys_info_page: program to output a system information page

PROGNAME="$(basename "$0")"
TITLE="System Information Report For $HOSTNAME"
CURRENT_TIME="$(date +"%x %r %Z")"
TIMESTAMP="Generated $CURRENT_TIME, by $USER"

report_uptime () {
	cat <<- _EOF_
		<h2>System Uptime</h2>
		<pre>$(uptime)</pre>
		_EOF_
	return
}

report_disk_space () {
	cat <<- _EOF_
		<h2>Disk Space Utilization</h2>
		<pre>$(df -h)</PRE>
		_EOF_
	return
}


report_home_space () {

	local format="%8s%10s%10s\n"
	local i dir_list total_files total_dirs total_size user_name

	if [[ "$(id -u)" -eq 0 ]]; then
		dir_list=/home/*
		user_name="All Users"
	else
		dir_list="$HOME"
		user_name="$USER"
	fi
	echo "<h2>Home Space Utilization ($user_name)</h2>"
	for i in $dir_list; do
		total_files="$(find "$i" -type f | wc -l)"
		total_dirs="$(find "$i" -type d | wc -l)"
		total_size="$(du -sh "$i" | cut -f 1)"
		echo "<h3>$i</h3>"
		echo "<pre>"
		printf "$format" "Dirs" "Files" "Size"
		printf "$format" "----" "-----" "----"
		printf "$format" "$total_dirs" "$total_files" "$total_size"
		echo "</pre>"
	done
	return
}

usage () {
	echo "$PROGNAME: usage: $PROGNAME [-f file | -i]"
	return
}

write_html_page () {
    # ----------- System Data Gathering -----------
    used_space=$(df / --output=used | tail -1)
    avail_space=$(df / --output=avail | tail -1)
    used_gb=$(awk "BEGIN {print $used_space/1024/1024}")
    avail_gb=$(awk "BEGIN {print $avail_space/1024/1024}")

    mem_total=$(free -m | awk '/Mem:/ {print $2}')
    mem_used=$(free -m | awk '/Mem:/ {print $3}')
    mem_free=$(free -m | awk '/Mem:/ {print $4}')

    # Get home directory sizes (Top 5)
    home_dirs=$(du -sh /home/* 2>/dev/null | sort -hr | head -n 5)
    home_labels=()
    home_values=()

    while read -r size path; do
        num=$(echo "$size" | grep -o '[0-9.]*')
        unit=$(echo "$size" | grep -o '[A-Za-z]*')
        case "$unit" in
            G|g) num=$(awk "BEGIN {print $num * 1024}") ;;
            K|k) num=$(awk "BEGIN {print $num / 1024}") ;;
        esac
        home_labels+=("$(basename "$path")")
        home_values+=("$num")
    done <<< "$home_dirs"

    home_labels_js=$(printf '"%s",' "${home_labels[@]}" | sed 's/,$//')
    home_values_js=$(printf '%s,' "${home_values[@]}" | sed 's/,$//')

    # ----------- HTML Generation -----------
    cat <<- _EOF_
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <title>$TITLE</title>
        <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
        <style>
            :root {
                --primary: #0078d7;
                --bg: #f4f7fb;
                --text: #333;
                --card-bg: #fff;
                --shadow: 0 2px 8px rgba(0,0,0,0.08);
            }
            body {
                font-family: "Segoe UI", Tahoma, sans-serif;
                background: var(--bg);
                color: var(--text);
                margin: 0;
                padding: 0;
            }
            header {
                background: var(--primary);
                color: white;
                padding: 20px 40px;
                text-align: center;
                box-shadow: var(--shadow);
            }
            header h1 {
                margin: 0;
                font-size: 1.8em;
            }
            main {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(380px, 1fr));
                gap: 20px;
                padding: 30px;
            }
            .card {
                background: var(--card-bg);
                border-radius: 10px;
                box-shadow: var(--shadow);
                padding: 20px;
                transition: transform 0.2s;
            }
            .card:hover {
                transform: translateY(-3px);
            }
            h2 {
                color: var(--primary);
                font-size: 1.2em;
                border-bottom: 2px solid var(--primary);
                padding-bottom: 5px;
                margin-bottom: 15px;
            }
            pre {
                background: #f8f9fb;
                padding: 10px;
                border-radius: 6px;
                overflow-x: auto;
                font-size: 0.9em;
            }
            canvas {
                width: 100%;
                max-height: 250px;
            }
            footer {
                text-align: center;
                padding: 20px;
                font-size: 0.85em;
                color: #777;
            }
            .download-btn {
                display: inline-block;
                background: var(--primary);
                color: white;
                padding: 10px 18px;
                border-radius: 6px;
                text-decoration: none;
                font-weight: 500;
                box-shadow: var(--shadow);
                transition: background 0.2s ease-in-out;
            }
            .download-btn:hover {
                background: #005fa3;
            }
        </style>
    </head>
    <body>
        <header>
            <h1>$TITLE</h1>
            <p>$TIMESTAMP</p>
        </header>

        <main>
            <div class="card">
                <h2>System Uptime</h2>
                <pre>$(uptime)</pre>
            </div>

            <div class="card">
                <h2>Disk Space Utilization</h2>
                <pre>$(df -h)</pre>
                <canvas id="diskChart"></canvas>
            </div>

            <div class="card">
                <h2>Memory Usage</h2>
                <pre>$(free -h)</pre>
                <canvas id="memoryChart"></canvas>
            </div>

            <div class="card">
                <h2>Home Directory Sizes (Top 5)</h2>
                <pre>$(du -sh /home/* 2>/dev/null | sort -hr | head -n 5)</pre>
                <canvas id="homeChart"></canvas>
            </div>
        </main>

        <footer>
            <button class="download-btn" onclick="downloadReport()"> ⬇ Download Report</button>
            <p>&copy; $(date +%Y) System Dashboard | Generated by $PROGNAME</p>
        </footer>

        <script>
            // -------- Chart.js Charts --------
            new Chart(document.getElementById('diskChart'), {
                type: 'doughnut',
                data: {
                    labels: ['Used (GB)', 'Available (GB)'],
                    datasets: [{
                        data: [${used_gb}, ${avail_gb}],
                        backgroundColor: ['#0078d7', '#cfd8dc']
                    }]
                },
                options: {
                    plugins: {
                        title: { display: true, text: 'Disk Usage (Root)' },
                        legend: { position: 'bottom' }
                    }
                }
            });

            new Chart(document.getElementById('memoryChart'), {
                type: 'pie',
                data: {
                    labels: ['Used (MB)', 'Free (MB)'],
                    datasets: [{
                        data: [${mem_used}, ${mem_free}],
                        backgroundColor: ['#ff6b6b', '#51cf66']
                    }]
                },
                options: {
                    plugins: {
                        title: { display: true, text: 'Memory Usage' },
                        legend: { position: 'bottom' }
                    }
                }
            });

            new Chart(document.getElementById('homeChart'), {
                type: 'bar',
                data: {
                    labels: [${home_labels_js}],
                    datasets: [{
                        label: 'Size (MB)',
                        data: [${home_values_js}],
                        backgroundColor: '#74c0fc'
                    }]
                },
                options: {
                    plugins: {
                        title: { display: true, text: 'Top 5 Home Directories' }
                    },
                    scales: {
                        y: { beginAtZero: true, title: { display: true, text: 'MB' } }
                    }
                }
            });

            // -------- Download Function --------
            function downloadReport() {
                const blob = new Blob([document.documentElement.outerHTML], {type: 'text/html'});
                const link = document.createElement('a');
                link.href = URL.createObjectURL(blob);
                link.download = 'system_report.html';
                link.click();
                URL.revokeObjectURL(link.href);
            }
        </script>
    </body>
    </html>
_EOF_
}


interactive=
filename=

while [[ -n "$1" ]]; do
	case "$1" in
		-f | --file)
			shift
			filename="$1"
                        ;;
		-i | --interactive)
			interactive=1
			;;
		-h | --help)
			usage
			exit
			;;
		*)
			usage >&2
			exit 1
			;;
	esac
	shift
done

# interactive mode

if [[ -n "$interactive" ]]; then
	while true; do
		read -p "Enter name of output file: " filename
		if [[ -e "$filename" ]]; then
			read -p "'$filename' exists. Overwrite? [y/n/q] > "
			case "$REPLY" in
				Y|y)
					break
					;;
				Q|q)
					echo "Program terminated."
					exit
					;;
				*)
					continue
					;;
			esac
		elif [[ -z "$filename" ]]; then
			continue
		else
			break
		fi
	done
fi

# output html page

if [[ -n "$filename" ]]; then
	if touch "$filename" && [[ -f "$filename" ]]; then
		write_html_page > "$filename"
	else
		echo "$PROGNAME: Cannot write file '$filename'" >&2
		exit 1
	fi
else
	write_html_page
fi