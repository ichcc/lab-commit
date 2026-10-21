resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = local.azs[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project}-public-nat-${local.azs[0]}"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.project}-public"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

module "fck_nat" {
  source = "git::https://github.com/RaJiska/terraform-aws-fck-nat.git?ref=v1.6.1"

  name          = "${var.project}-nat"
  vpc_id        = aws_vpc.this.id
  subnet_id     = aws_subnet.public.id
  instance_type = var.nat_instance_type
  ha_mode       = true

  update_route_tables = true
  route_tables_ids = {
    private = aws_route_table.private.id
  }

  depends_on = [aws_internet_gateway.this]
}
