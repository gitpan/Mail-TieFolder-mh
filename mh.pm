package Mail::TieFolder::mh;

require 5.005_62;
use strict;
use warnings;
use Carp;
use Mail::Internet;
use File::Temp qw/ tempfile /;

our $VERSION = '0.03';

=head1 NAME

Mail::TieFolder::mh - Tied hash interface for mh mail folders

=head1 SYNOPSIS

  use Mail::TieFolder::mh;
  tie (%inbox, 'Mail::TieFolder::mh', 'inbox');

  # get list of all message IDs in folder
  @messageIDs = keys (%inbox);

  # fetch message by ID 
  $msg = $inbox{'9287342.2138749@foo.com'};

=head1 DESCRIPTION

Mail::TieFolder::mh implements a tied hash interface to the mh folder
format.

=cut

sub TIEHASH
{
  my ($class, $folder, $rargs) = @_;

  # warn @Mail::TieFolder::ISA;
  
  my $self={};
  $self->{'folder'} = $folder;
  for(keys %$rargs)
  {
    $self->{$_} = $rargs->{$_};
  }
  bless $self, ref($class) ? ref($class) : $class;
  $self->{'unseen'} = 1 unless exists $self->{'unseen'};

  chomp(my $path = `mhparam Path`);
  die "can't find mh base directory" unless $path;
  `mkdir -p $ENV{HOME}/$path/$folder`; # make sure folder exists

  # BUG -- FIRSTKEY/NEXTKEY won't work if you do a packf after TIEHASH
  open(SCAN, "scan +$folder -width 9999 -format '%(msg) %{message-id}' 2>/dev/null |") || die $!;
  my ($num, $id);
  while(<SCAN>)
  {
    chomp;
    ($num, $id) = split;
    $self->id2num($id,$num);
    $self->num2id($num,$id);
    $self->{'firstnum'} = $num unless $self->{'firstnum'};
    $self->{'lastnum'} = $num;
  }
  return $self;
}

sub FETCH
{
  my ($self,$id) = @_;
  chomp($id);
  my $folder = $self->{'folder'};
  my $cmd = "pick +$folder --message-id '$id' 2> /dev/null ";
  # warn $cmd;
  chomp(my $msgnum = `$cmd`);
  # warn "\n\n$?\n\n";
  # warn "$id $msgnum\n";
  return undef if $? >> 8;
  return undef unless $msgnum;
  open(MSG, "show -nohead -noshowproc +$folder $msgnum |") || die $!;
  # my $msg = join('',<MSG>);
  my $msg = new Mail::Internet \*MSG;
  return undef unless $msg;
  chomp(my $testid = $msg->head->get('Message-Id'));
  # warn "\n$id $testid\n";
  return undef unless $id eq $testid;
  $self->id2num($id,$msgnum);
  $self->num2id($msgnum,$id);
  if ($self->{'unseen'})
  {
    `mark +$folder $msgnum -seq unseen`;
    die "cannot mark unseen: message $msgnum in folder $folder" if $? >> 8;
  }
  return $msg;
}

sub FIRSTKEY
{
  my ($self) = @_;
  my $id = $self->num2id($self->{'firstnum'});
  return $id;
}

sub NEXTKEY
{
  my ($self,$id) = @_;
  chomp($id);
  my $nextid;
  for(my $num=$self->id2num($id) + 1; $num <= $self->{'lastnum'}; $num++)
  {
    # warn $num;
    last if ($nextid = $self->num2id($num))
  }
  return $nextid;
}

sub EXISTS
{
  my ($self,$id) = @_;
  chomp($id);
  return $self->FETCH($id);
}

# $h{'new'} to create new
# $h{$id} to overwrite
sub STORE
{
  my ($self,$oldid,$msg) = @_;
  my $oldmsg;
  chomp($oldid);
  chomp(my $newid = $msg->head->get('Message-Id'));
  return undef unless $oldid eq $newid || $oldid eq 'new';
  if ($self->EXISTS($newid))
  {
    return undef if $oldid eq 'new';
    $oldmsg = $self->DELETE($newid); 
  }
  my ($tmpfh, $tmpname) = tempfile();
  print $tmpfh $msg->as_string();
  close $tmpfh;
  my $folder = $self->{'folder'};
  `inc +$folder -silent -file $tmpname`;
  die if $? >> 8;
  unlink($tmpname) || die $!;
  $msg = $self->FETCH($newid);
  die unless $msg;
  if ($self->{'unseen'})
  {
    my $msgnum = $self->id2num($newid);
    `mark +$folder $msgnum -seq unseen`;
    die "cannot mark unseen: message $msgnum in folder $folder" if $? >> 8;
  }
  return $oldmsg if $oldmsg;
  return $msg;
}

sub DELETE
{
  my ($self,$id) = @_;
  chomp($id);
  my $folder = $self->{'folder'};
  my $msg = $self->FETCH($id);
  return undef unless $msg;
  my $num = $self->id2num($id);
  die unless $num;
  `rmm +$folder $num`;
  die if $? >> 8;
  $self->id2num($id,0);
  $self->num2id($num,"");
  return $msg;
}




sub num2id
{
  my $self=shift;
  my $num=shift;
  my $id=shift;
  chomp($id) if $id;
  $self->{'num2id'}{$num} = $id if $id;
  $id = $self->{'num2id'}{$num};
  return $id;
}

sub id2num
{
  my $self=shift;
  my $id=shift;
  my $num=shift;
  chomp($id);
  $self->{'id2num'}{$id} = $num if $num;
  $num = $self->{'id2num'}{$id};
  return $num;
}

=head1 AUTHOR

Steve Traugott, stevegt@TerraLuna.Org

=head1 SEE ALSO

perltie(1)

=cut

1;

__END__
