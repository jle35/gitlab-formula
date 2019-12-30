{% from "gitlab/map.jinja" import gitlab with context %}

{% if grains['os_family'] == 'Debian' %}
gitlab-runner repo:
  pkgrepo.managed:
    - humanname: gitlab-runner debian repo
    - file: /etc/apt/sources.list.d/gitlab-runner.list
    - name: deb https://packages.gitlab.com/runner/gitlab-runner/{{ grains['os']|lower }}/ {{ grains['oscodename'] }} main
    - key_url: https://packages.gitlab.com/runner/gitlab-runner/gpgkey
    - require_in:
      - pkg: gitlab-install_pkg

gitlab-install_pkg:
  pkg.installed:
    - name: gitlab-runner
{% else %}
gitlab-install_pkg:
  pkg.installed:
    - sources:
      - gitlab-runner: {{gitlab.runner.downloadpath}}
{% endif %}

gitlab-runner_unregister:
  cmd.run:
    - name: gitlab-runner unregister --all-runners
    - require:
      - pkg: gitlab-install_pkg

{% for service_name, service in gitlab.runner.services.items() %}
{% set group = service.group|default(service.username, true) %}
{% set home = service.home|default("/home/" ~ service.username, true) %}
{% set working_directory = service.working_directory|default(home, true) %}

# reinstall service with proper user
gitlab-runner-uninstall_{{ service_name }}:
  cmd.run:
    - name: gitlab-runner uninstall --service {{ service_name }}
    - onlyif: gitlab-runner restart --service {{ service_name }} 
    - require:
      - pkg: gitlab-install_pkg
      - cmd: gitlab-runner_unregister

gitlab-runner-install_{{ service_name }}:
  cmd.run:
    - name: gitlab-runner install -user {{ service.username }} --service {{ service_name }} --working-directory {{ working_directory }}
    - watch:
      - cmd: gitlab-runner-uninstall_{{ service_name }}

gitlab-create_group_{{service_name }}_{{ group }}:
  group.present:
    - name: {{ group }}
    - system: True
    - require:
      - pkg: gitlab-install_pkg

gitlab-install_runserver_create_user_{{ service_name }}_{{ service.username }}:
  user.present:
    - name: {{service.username}}
    - shell: /bin/false
    - home: {{ home }}
    - groups:
      - {{ group }}
    - require:
      - group: gitlab-create_group_{{ service_name }}_{{ group }}

{% for runner_name, runner in service.runners.items() %}
gitlab-install_runserver3_{{ service_name }}_{{ runner_name }}:
  cmd.run:
    - name: "/usr/bin/gitlab-runner register --non-interactive {% for arg, val in runner.items() %} --{{arg}} '{{ val }}' {% endfor %} --name {{ runner_name }}"
    - unless: gitlab-runner verify -n {{ runner_name }}
    - require:
      - user: gitlab-install_runserver_create_user_{{ service_name }}_{{ service.username }}
    - require_in:
      - service: gitlab-service_{{ service_name}}
{% endfor %}

gitlab-service_{{ service_name }}:
  service.running:
    - name: {{ service_name }}
    - enable: True
    - require:
      - pkg: gitlab-install_pkg
    - watch:
      - cmd: gitlab-runner-install_{{ service_name }}
{% endfor %}
