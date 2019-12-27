# vim: sts=2 ts=2 sw=2 et ai
#
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
      - gitlab-runner: {{gitlab.runners.downloadpath}}
{% endif %}

gitlab-reinstall_with_good_user:
  cmd.run:
    - name: gitlab-runner uninstall && gitlab-runner install -user {{ gitlab.runners.username }}
    - require:
      - pkg: gitlab-install_pkg

gitlab-create_group:
  group.present:
    - name: {{ gitlab.runners.username
    - system: True
    - require:
      - pkg: gitlab-install_pkg

gitlab-install_runserver_create_user:
  user.present:
    - name: {{gitlab.runners.username}}
    - shell: /bin/false
    - home: {{gitlab.runners.home}}
    - groups:
      - gitlab-runner
    - require:
      - group: gitlab-create_group

{% for runner, runner_name in gitlab.runners }}
gitlab-install_runserver3:
  cmd.run:
    - name: "CI_SERVER_URL='{{runner.url}}' REGISTRATION_TOKEN='{{runner.token}}' RUNNER_EXECUTOR='{{runner.executor}}' /usr/bin/gitlab-runner  register --non-interactive --builds-dir '{{ runner.home }}' --name {{ runner.name }} "
    - onlyif: gitlab-runner verify -n {{ runner_name }}
    - require:
      - user: gitlab-install_runserver_create_user
    - require_in:
      - service: - gitlab-runner

{% endfor %}

gitlab-runner:
  service.running:
    - enable: True
    - require:
      - pkg: gitlab-install_pkg
      - cmd: gitlab-install_runserver3


