#
# (c) Jan Gehring <jan.gehring@gmail.com>
# 
# vim: set ts=3 sw=3 tw=0:
# vim: set expandtab:

=head1 NAME

Rex::Template - Simple Template Engine.

=head1 DESCRIPTION

This is a simple template engine for configuration files.

=head1 SYNOPSIS

 my $template = Rex::Template->new;
 print $template->parse($content, \%template_vars);

=head1 EXPORTED FUNCTIONS

=over 4

=cut


package Rex::Template;


use strict;
use warnings;

use Rex::Config;
use Rex::Logger;

our $DO_CHOMP = 0;
our $BE_LOCAL = 1;

sub function {
   my ($class, $name, $code) = @_;
   
   no strict 'refs';
   *{ $class . "::" . $name } = $code;
   use strict;
}

sub new {
   my $that = shift;
   my $proto = ref($that) || $that;
   my $self = { @_ };

   bless($self, $proto);

   return $self;
}

sub parse {
   my $self = shift;
   my $data = shift;

   my $vars = {};

   if(ref($_[0]) eq "HASH") {
      $vars = shift;
   }
   else {
      $vars = { @_ };
   }

   my $new_data;
   my $r="";

   my $config_values = Rex::Config->get_all;
   for my $key (keys %{ $config_values }) {
      if(! exists $vars->{$key}) {
         $vars->{$key} = $config_values->{$key};
      }
   }

   my $do_chomp = 0;
   $new_data = join("\n", map {
      my ($code, $type, $text) = ($_ =~ m/(\<%)*([+=])*(.+)%\>/s);

      if($code) {
         my $pcmd = substr($text, -1);
         if($pcmd eq "-") {
            $text = substr($text, 0, -1);
            $do_chomp = 1;
         }

         my($var_type, $var_name) = ($text =~ m/([\$])::([a-zA-Z0-9_]+)/);

         if($var_name && ! ref($vars->{$var_name}) && ! $BE_LOCAL) {
            $text =~ s/([\$])::([a-zA-Z0-9_]+)/$1\{\$$2\}/g;
         }
         elsif($var_name && ! ref($vars->{$var_name}) && $BE_LOCAL) {
            $text =~ s/([\$])::([a-zA-Z0-9_]+)/$1$2/g;
         }
         else {
            $text =~ s/([\$])::([a-zA-Z0-9_]+)/\$$2/g;
         }

         if($type && $type =~ m/^[+=]$/) {
            $_ = "\$r .= $text;";
         }
         else {
            $_ = $text;
         }

      } 
      
      else {
         if($DO_CHOMP || $do_chomp) {
            chomp $_;
            $do_chomp = 0;
         }
         $_ = '$r .= "' . _quote($_) . '";';


      }

   } split(/(\<%.*?%\>)/s, $data));

   eval {
      no strict 'refs';
      no strict 'vars';

      for my $var (keys %{$vars}) {
         Rex::Logger::debug("Registering: $var");
         unless(ref($vars->{$var})) {
            $$var = \$vars->{$var};
         } else {
            $$var = $vars->{$var};
         }
      }

      if($BE_LOCAL == 1) {
         my $var_data = '
        
        return sub {
           my $r = "";
           my (
         
         ';

         my @code_values;
         for my $var (keys %{$vars}) {
            Rex::Logger::debug("Registering local: $var");
            $var_data .= '$' . $var . ", \n";
            push(@code_values, $vars->{$var});
         }

         $var_data .= '$this_is_really_nothing) = @_;';
         $var_data .= "\n";

         $var_data .= $new_data;

         $var_data .= "\n";
         $var_data .= ' return $r;';
         $var_data .= "\n};";

         Rex::Logger::debug("BE_LOCAL==1");
         Rex::Logger::debug($var_data);

         my $tpl_code = eval($var_data);
         $r = $tpl_code->(@code_values);

      }
      else {
         Rex::Logger::debug("BE_LOCAL==0");
         Rex::Logger::debug($new_data);
         $r = eval($new_data);
      }

      # undef the vars
      for my $var (keys %{$vars}) {
         $$var = undef;
      }

      if($@) {
         Rex::Logger::info($@);
      }

   };

   return $r;
}

sub _quote {
   my ($str) = @_;

   $str =~ s/\\/\\\\/g;
   $str =~ s/"/\\"/g;
   $str =~ s/\@/\\@/g;
   $str =~ s/\%/\\%/g;
   $str =~ s/\$/\\\$/g;

   return $str;
}

=item is_defined($variable, $default_value)

This function will check if $variable is defined. If it is defined it will return the value of $variable. If not, it will return $default_value.

You can use this function inside your templates.

 ServerTokens <%= is_defined($::server_tokens, "Prod") %>

=cut

sub is_defined {
   my ($check_var, $default) = @_;
   if(defined $check_var) { return $check_var; }

   return $default;
}

=back

=cut

1;

